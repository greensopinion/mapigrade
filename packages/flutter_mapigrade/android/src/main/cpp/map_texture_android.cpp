// Android render target (designs D51, D54 and D58 of the
// android-texture-vertical-slice change, D130 to D137 of the
// android-layer-children-alignment change). MapLibre renders through an EGL
// window surface on the Surface of an ImageReader that MapSurface owns. Its
// buffers are HardwareBuffers that Flutter samples through an image texture,
// so no pixels are copied and none pass through CPU memory. The session is
// dedicated: it owns the map thread's EGL context.
//
// Each frame carries its frame id as its presentation time. MapSurface's
// listener thread passes each image to OnFrameImage, which publishes the frame
// into its display slot; the target keeps a global reference to the image of
// each slot. When Dart chooses a frame, FrameAvailable gives its image to
// Flutter, and SlotFreed closes the image when the slot becomes free. Both run
// under the BufferState lock.
//
// Threads: MapSurface is created, resized and released on Android's main
// thread, which is also Dart's UI thread. The reader's Surface goes to the map
// thread as an ANativeWindow in a target task, and the map thread creates the
// EGL objects. While the activity is stopped, the session presents to a 1x1
// pbuffer surface and no frame is rendered. The map thread never calls into
// Java.
#include <EGL/egl.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <dirent.h>
#include <dlfcn.h>
#include <jni.h>
#include <unistd.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

#include "map_texture.h"
#include "map_texture_api.h"
#include "render_target.h"

namespace map_texture {
namespace {

#define LOGE(...) \
  __android_log_print(ANDROID_LOG_ERROR, "flutter_mapigrade", __VA_ARGS__)

// Set by JNI_OnLoad and nativeInit; the references are global.
JavaVM* java_vm = nullptr;
jclass map_surface_class = nullptr;
jmethodID map_surface_init = nullptr;
jmethodID map_surface_id = nullptr;
jmethodID map_surface_resize = nullptr;
jmethodID map_surface_release = nullptr;
jmethodID map_surface_push = nullptr;
jmethodID map_surface_close_image = nullptr;
jmethodID map_surface_release_readers = nullptr;
std::mutex cache_dir_mutex;
std::string cache_dir;

// The TextureRegistry of each engine that attached the plugin, as a global
// reference, by token (design D153 of the multiple-flutter-engines change).
// nativeInit adds an engine's registry and nativeDetach removes it.
std::mutex registries_mutex;
int64_t next_token = 1;
std::unordered_map<int64_t, jobject>& Registries() {
  static auto* registries = new std::unordered_map<int64_t, jobject>();
  return *registries;
}

// A local reference to the registry of the engine `engine`, or null.
jobject NewRegistryRef(JNIEnv* env, int64_t engine) {
  std::lock_guard lock(registries_mutex);
  auto it = Registries().find(engine);
  return it == Registries().end() ? nullptr : env->NewLocalRef(it->second);
}

// The JNIEnv of the calling thread, which must be attached to the VM (the main
// thread is).
JNIEnv* Env() {
  JNIEnv* env = nullptr;
  if (java_vm == nullptr ||
      java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) !=
          JNI_OK) {
    return nullptr;
  }
  return env;
}

bool OnMainThread() { return gettid() == getpid(); }

// Clears and logs a pending Java exception; returns whether there was one.
bool CheckException(JNIEnv* env, const char* what) {
  if (!env->ExceptionCheck()) return false;
  env->ExceptionDescribe();
  env->ExceptionClear();
  LOGE("%s threw an exception", what);
  return true;
}

using WindowRef = std::shared_ptr<ANativeWindow>;

WindowRef WindowFromSurface(JNIEnv* env, jobject surface) {
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return nullptr;
  return WindowRef(window, ANativeWindow_release);
}

using PresentationTimeFn = EGLBoolean (*)(EGLDisplay, EGLSurface, int64_t);

std::string EglError(const char* what) {
  char message[96];
  std::snprintf(message, sizeof(message), "%s failed with EGL error 0x%x", what,
                eglGetError());
  return message;
}

class AndroidSurfaceTarget;

// The live targets, so that the plugin can release and restore their readers
// when the activity stops and starts (design D137). Main thread only.
std::set<AndroidSurfaceTarget*>& Targets() {
  static std::set<AndroidSurfaceTarget*> targets;
  return targets;
}

class AndroidSurfaceTarget : public SurfaceRenderTarget {
 public:
  AndroidSurfaceTarget(std::weak_ptr<MapTexture> owner)
      : owner_(std::move(owner)) {
    Targets().insert(this);
  }

  ~AndroidSurfaceTarget() override {
    Targets().erase(this);
    // Unregister() released MapSurface; this covers a failed create.
    if (map_surface_ != nullptr) {
      if (JNIEnv* env = Env()) env->DeleteGlobalRef(map_surface_);
    }
  }

  // Main thread. Creates the image texture in `registry` through MapSurface.
  bool Init(JNIEnv* env, jobject registry) {
    jobject local = env->NewObject(map_surface_class, map_surface_init,
                                   registry, reinterpret_cast<jlong>(this));
    if (CheckException(env, "creating the image texture") ||
        local == nullptr) {
      return false;
    }
    map_surface_ = env->NewGlobalRef(local);
    env->DeleteLocalRef(local);
    texture_id_ = env->CallLongMethod(map_surface_, map_surface_id);
    return !CheckException(env, "MapSurface.id");
  }

  // Six display slots share the one image texture (designs D133 and D135).
  int slot_count() const override { return kChoiceReleasedBufferCount; }
  int64_t texture_id(int) const override { return texture_id_; }

  // Main thread. A new physical size makes MapSurface create a reader of that
  // size, whose Surface replaces the window on the map thread before the map
  // thread applies the resize (design D136).
  void WillResize(const TargetSize& size) override {
    if (size.physical_width == requested_width_ &&
        size.physical_height == requested_height_) {
      return;
    }
    requested_width_ = size.physical_width;
    requested_height_ = size.physical_height;
    if (!released_) CreateReader();
  }

  // Main thread, when the activity stops (design D137). Returns when the map
  // thread no longer uses the reader's surface, and the slots' images and
  // the readers are closed.
  void ReleaseReader() {
    if (released_) return;
    released_ = true;
    auto owner = owner_.lock();
    if (!owner) return;
    owner->RunTargetTask(
        [this](mln_render_session session, const TargetSize& size) {
          Park(session, size);
        },
        /*wait=*/true);
    owner->ResetSlots();
    JNIEnv* env = Env();
    if (env == nullptr || map_surface_ == nullptr) return;
    CloseDeferredImages(env);
    env->CallVoidMethod(map_surface_, map_surface_release_readers);
    CheckException(env, "MapSurface.releaseReaders");
  }

  // Main thread, when the activity starts: creates a reader for the map to
  // render into again.
  void RestoreReader() {
    if (!released_) return;
    released_ = false;
    CreateReader();
  }

  // MapSurface's listener thread: the image of frame `frame_id` arrived.
  // Returns whether a slot keeps it; otherwise the caller closes it.
  bool OnFrameImage(JNIEnv* env, uint64_t frame_id, jobject image) {
    auto owner = owner_.lock();
    if (!owner) return false;
    return owner->OnFrameImage(frame_id, [&](int slot) {
      CloseDeferredImages(env);
      images_[slot] = env->NewGlobalRef(image);
    });
  }

  // Main thread, under the BufferState lock (design D132).
  void FrameAvailable(int slot) override {
    JNIEnv* env = Env();
    if (env == nullptr || map_surface_ == nullptr) return;
    CloseDeferredImages(env);
    if (images_[slot] == nullptr) return;
    env->CallVoidMethod(map_surface_, map_surface_push, images_[slot]);
    CheckException(env, "MapSurface.push");
  }

  // Under the BufferState lock, on the main thread, the listener thread or
  // the map thread (design D133). The map thread frees a slot with an image
  // when render_update queued a frame on the surface but reported none; it
  // doesn't call into Java, so the image is closed by the next call on another
  // thread.
  void SlotFreed(int slot) override {
    if (images_[slot] == nullptr) return;
    JNIEnv* env = Env();
    if (env == nullptr) {
      std::lock_guard lock(deferred_mutex_);
      deferred_images_.push_back(images_[slot]);
      images_[slot] = nullptr;
      return;
    }
    CloseImage(env, slot);
  }

  // Map thread.

  // Sets the frame id as the presentation time of the next frame that the
  // session queues on the window, so that the image tells which frame it
  // holds (design D131).
  void WillRender(uint64_t frame_id) override {
    if (window_surface_ == EGL_NO_SURFACE || presentation_time_ == nullptr) {
      return;
    }
    if (!presentation_time_(display_, window_surface_,
                            static_cast<int64_t>(frame_id))) {
      Report(EglError("eglPresentationTimeANDROID"));
    }
  }

  mln_status Attach(mln_map map, const TargetSize& size,
                    mln_render_session* out_session) override {
    if (!EnsureDisplay()) return MLN_STATUS_NATIVE_ERROR;
    EGLSurface surface = CurrentSurface();
    if (surface == EGL_NO_SURFACE) return MLN_STATUS_NATIVE_ERROR;
    mln_opengl_surface_descriptor descriptor = Descriptor(size, surface);
    mln_status status = mln_opengl_surface_attach(map, &descriptor, out_session);
    // The dedicated session has made its context current on `surface`.
    if (status == MLN_STATUS_OK && surface == window_surface_) {
      SetNonBlockingSwap();
    }
    return status;
  }

  mln_status SetTarget(mln_render_session session,
                       const TargetSize& size) override {
    EGLSurface surface = CurrentSurface();
    if (surface == EGL_NO_SURFACE) return MLN_STATUS_NATIVE_ERROR;
    mln_opengl_surface_descriptor descriptor = Descriptor(size, surface);
    return mln_opengl_surface_set_target(session, &descriptor);
  }

  bool CanPresent() const override { return window_surface_ != EGL_NO_SURFACE; }

  void ReleaseSurfaces() override {
    if (display_ == EGL_NO_DISPLAY) return;
    // The session's context was released with the session.
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    DestroyWindowSurface();
    if (pbuffer_ != EGL_NO_SURFACE) {
      eglDestroySurface(display_, pbuffer_);
      pbuffer_ = EGL_NO_SURFACE;
    }
    // The display is the process's default display, which Flutter may use
    // too, so it is not terminated.
    eglReleaseThread();
  }

  // The thread that disposes the map (the main thread), after the map thread
  // has stopped.
  void Unregister() override {
    JNIEnv* env = Env();
    if (env == nullptr || map_surface_ == nullptr) return;
    // Stops the listener thread and closes every image.
    env->CallVoidMethod(map_surface_, map_surface_release);
    CheckException(env, "MapSurface.release");
    for (jobject& image : images_) {
      if (image != nullptr) env->DeleteGlobalRef(image);
      image = nullptr;
    }
    {
      std::lock_guard lock(deferred_mutex_);
      for (jobject image : deferred_images_) env->DeleteGlobalRef(image);
      deferred_images_.clear();
    }
    env->DeleteGlobalRef(map_surface_);
    map_surface_ = nullptr;
  }

 private:
  // Main thread. Creates a reader of the requested size and sends its
  // surface to the map thread. Before the first resize there is no size.
  void CreateReader() {
    if (requested_width_ == 0 || requested_height_ == 0) return;
    JNIEnv* env = Env();
    if (env == nullptr || map_surface_ == nullptr) return;
    jobject surface = env->CallObjectMethod(
        map_surface_, map_surface_resize, static_cast<jint>(requested_width_),
        static_cast<jint>(requested_height_));
    if (CheckException(env, "MapSurface.resize") || surface == nullptr) {
      return;
    }
    SendWindow(WindowFromSurface(env, surface));
    env->DeleteLocalRef(surface);
  }

  // Main thread. Queues the replacement of the window for the map thread. If
  // the map thread stops first, the task is dropped and releases the window.
  void SendWindow(WindowRef window) {
    if (window == nullptr) {
      LOGE("ANativeWindow_fromSurface returned null");
      return;
    }
    if (auto owner = owner_.lock()) {
      owner->RunTargetTask(
          [this, window](mln_render_session session, const TargetSize& size) {
            ReplaceWindow(window, session, size);
          },
          /*wait=*/false);
    }
  }

  // Map thread. Creates the window surface on `window` and makes the session
  // present through it. The previous window surface is destroyed after the
  // switch, and its window released.
  void ReplaceWindow(WindowRef window, mln_render_session session,
                     const TargetSize& size) {
    if (!EnsureDisplay()) return;
    EGLSurface surface =
        eglCreateWindowSurface(display_, config_, window.get(), nullptr);
    if (surface == EGL_NO_SURFACE) {
      Report(EglError("eglCreateWindowSurface"));
      return;
    }
    EGLSurface previous = window_surface_;
    WindowRef previous_window = std::move(window_);
    window_surface_ = surface;
    window_ = std::move(window);
    if (session != MLN_HANDLE_NULL) {
      SwitchSession(session, size, surface);
    }
    if (previous != EGL_NO_SURFACE) eglDestroySurface(display_, previous);
  }

  // Map thread. Moves the session to the pbuffer surface and destroys the
  // window surface, so that the window is no longer used.
  void Park(mln_render_session session, const TargetSize& size) {
    if (window_surface_ == EGL_NO_SURFACE) return;
    if (session != MLN_HANDLE_NULL) {
      if (!EnsurePbuffer()) return;
      SwitchSession(session, size, pbuffer_);
    }
    DestroyWindowSurface();
  }

  // Map thread. Makes the session present through `surface`, and makes it
  // current at once: set_target makes it current only on the next render
  // (surface.h), and until then EGL would keep using the previous surface.
  void SwitchSession(mln_render_session session, const TargetSize& size,
                     EGLSurface surface) {
    mln_opengl_surface_descriptor descriptor = Descriptor(size, surface);
    mln_status status = mln_opengl_surface_set_target(session, &descriptor);
    if (status != MLN_STATUS_OK) {
      Report("mln_opengl_surface_set_target failed with status " +
             std::to_string(static_cast<int>(status)));
      return;
    }
    EGLContext context = eglGetCurrentContext();
    if (context == EGL_NO_CONTEXT) return;
    if (!eglMakeCurrent(display_, surface, surface, context)) {
      Report(EglError("eglMakeCurrent"));
      return;
    }
    if (surface == window_surface_) SetNonBlockingSwap();
  }

  // Closes the images of slots that the map thread freed.
  void CloseDeferredImages(JNIEnv* env) {
    std::lock_guard lock(deferred_mutex_);
    for (jobject image : deferred_images_) {
      env->CallVoidMethod(map_surface_, map_surface_close_image, image);
      CheckException(env, "MapSurface.closeImage");
      env->DeleteGlobalRef(image);
    }
    deferred_images_.clear();
  }

  // Closes the image of `slot`, if it has one.
  void CloseImage(JNIEnv* env, int slot) {
    if (images_[slot] == nullptr) return;
    env->CallVoidMethod(map_surface_, map_surface_close_image, images_[slot]);
    CheckException(env, "MapSurface.closeImage");
    env->DeleteGlobalRef(images_[slot]);
    images_[slot] = nullptr;
  }

  // Map thread, with a window surface current. With swap interval 0 the
  // window queues frames in async mode: a frame replaces a queued frame that
  // the listener hasn't acquired yet, and eglSwapBuffers never waits for a
  // buffer to be released. A swap that waited could deadlock with the main
  // thread's waits for the map thread (dispose, activity stop) (design D53;
  // D131 keeps it).
  void SetNonBlockingSwap() {
    if (!eglSwapInterval(display_, 0)) Report(EglError("eglSwapInterval"));
  }

  void DestroyWindowSurface() {
    if (window_surface_ != EGL_NO_SURFACE) {
      eglDestroySurface(display_, window_surface_);
      window_surface_ = EGL_NO_SURFACE;
    }
    window_.reset();
  }

  // The surface the session presents through: the window, or the pbuffer
  // while Flutter has removed the window.
  EGLSurface CurrentSurface() {
    if (window_surface_ != EGL_NO_SURFACE) return window_surface_;
    return EnsurePbuffer() ? pbuffer_ : EGL_NO_SURFACE;
  }

  bool EnsureDisplay() {
    if (display_ != EGL_NO_DISPLAY) return true;
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) {
      Report(EglError("eglInitialize"));
      return false;
    }
    // One config serves the window surface and the pbuffer surface.
    const EGLint attributes[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_SURFACE_TYPE,    EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
        EGL_RED_SIZE,        8,
        EGL_GREEN_SIZE,      8,
        EGL_BLUE_SIZE,       8,
        EGL_ALPHA_SIZE,      8,
        EGL_DEPTH_SIZE,      24,
        EGL_STENCIL_SIZE,    8,
        EGL_NONE,
    };
    EGLint count = 0;
    if (!eglChooseConfig(display, attributes, &config_, 1, &count) ||
        count < 1) {
      Report("no EGL config supports OpenGL ES 3 window and pbuffer surfaces");
      return false;
    }
    display_ = display;
    presentation_time_ = reinterpret_cast<PresentationTimeFn>(
        eglGetProcAddress("eglPresentationTimeANDROID"));
    if (presentation_time_ == nullptr) {
      Report("eglPresentationTimeANDROID isn't available");
    }
    return true;
  }

  bool EnsurePbuffer() {
    if (pbuffer_ != EGL_NO_SURFACE) return true;
    if (!EnsureDisplay()) return false;
    const EGLint attributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    pbuffer_ = eglCreatePbufferSurface(display_, config_, attributes);
    if (pbuffer_ == EGL_NO_SURFACE) {
      Report(EglError("eglCreatePbufferSurface"));
      return false;
    }
    return true;
  }

  mln_opengl_surface_descriptor Descriptor(const TargetSize& size,
                                           EGLSurface surface) {
    mln_opengl_surface_descriptor descriptor =
        mln_opengl_surface_descriptor_default();
    descriptor.extent = size.extent;
    descriptor.context.size = sizeof(descriptor.context);
    descriptor.context.platform = MLN_OPENGL_CONTEXT_PLATFORM_EGL;
    descriptor.context.ownership = MLN_OPENGL_CONTEXT_OWNERSHIP_DEDICATED;
    descriptor.context.data.egl.size = sizeof(descriptor.context.data.egl);
    descriptor.context.data.egl.display = display_;
    descriptor.context.data.egl.config = config_;
    descriptor.context.data.egl.share_context = nullptr;
    descriptor.context.data.egl.client_api = MLN_OPENGL_CLIENT_API_GLES;
    descriptor.surface = surface;
    return descriptor;
  }

  void Report(const std::string& message) {
    LOGE("%s", message.c_str());
    if (auto owner = owner_.lock()) owner->ReportRenderError(message);
  }

  const std::weak_ptr<MapTexture> owner_;

  // Main thread.
  jobject map_surface_ = nullptr;
  // The image of each slot, guarded by the BufferState lock (and used on the
  // main thread after the map thread has stopped).
  jobject images_[kMaxBufferCount] = {};
  // Images of slots that the map thread freed, to close on another thread.
  std::mutex deferred_mutex_;
  std::vector<jobject> deferred_images_;
  int64_t texture_id_ = 0;
  uint32_t requested_width_ = 0;
  uint32_t requested_height_ = 0;
  // Whether ReleaseReader() released the reader.
  bool released_ = false;

  // Map thread.
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLConfig config_ = nullptr;
  WindowRef window_;
  EGLSurface window_surface_ = EGL_NO_SURFACE;
  EGLSurface pbuffer_ = EGL_NO_SURFACE;
  PresentationTimeFn presentation_time_ = nullptr;
};

// Main thread. Releases or restores the reader of every map (design D137).
void SetReadersReleased(bool released) {
  // A copy: a release waits for the map thread, and no target is created or
  // destroyed meanwhile, but the set is not iterated across the waits.
  std::set<AndroidSurfaceTarget*> targets = Targets();
  for (AndroidSurfaceTarget* target : targets) {
    if (released) {
      target->ReleaseReader();
    } else {
      target->RestoreReader();
    }
  }
}

}  // namespace

std::unique_ptr<RenderTarget> CreatePlatformRenderTarget(
    std::weak_ptr<MapTexture> owner, bool copy_free, int64_t engine,
    std::string* out_error) {
  // MapSurface belongs to the main thread, which runs Dart's UI
  // isolate unless the merged platform and UI thread is turned off.
  if (!OnMainThread()) {
    LOGE("map_texture_create must be called on the main thread; is the merged "
         "platform and UI thread turned off?");
    return nullptr;
  }
  JNIEnv* env = Env();
  if (env == nullptr || map_surface_class == nullptr) {
    LOGE("map_texture_create called before the plugin was attached");
    return nullptr;
  }
  jobject registry = NewRegistryRef(env, engine);
  if (registry == nullptr) {
    *out_error = kEngineDetachedError;
    return nullptr;
  }
  auto target = std::make_unique<AndroidSurfaceTarget>(std::move(owner));
  bool initialized = target->Init(env, registry);
  env->DeleteLocalRef(registry);
  if (!initialized) return nullptr;
  return target;
}

std::string PlatformCachePath() {
  std::lock_guard lock(cache_dir_mutex);
  if (cache_dir.empty()) return {};
  return cache_dir + "/flutter_mapigrade.db";
}

// The FFI reads /android_asset/ from the APK's assets/ directory.
std::string PlatformAssetPath() { return "/android_asset/flutter_assets"; }

void RunInPlatformScope(const std::function<void()>& work) { work(); }

}  // namespace map_texture

using map_texture::AndroidSurfaceTarget;

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
  map_texture::java_vm = vm;
  return JNI_VERSION_1_6;
}

// Returns the token of the engine's registry (design D153), or 0 if the
// plugin can't create maps.
JNIEXPORT jlong JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapigradePlugin_nativeInit(
    JNIEnv* env, jobject, jobject registry, jobject context,
    jstring cache_dir) {
  using namespace map_texture;
  if (map_surface_class == nullptr) {
    jclass surface_class =
        env->FindClass("com/greensopinion/flutter_mapigrade/MapSurface");
    if (CheckException(env, "FindClass(MapSurface)") || surface_class == nullptr) {
      return 0;
    }
    map_surface_class = static_cast<jclass>(env->NewGlobalRef(surface_class));
    env->DeleteLocalRef(surface_class);
    map_surface_init = env->GetMethodID(map_surface_class, "<init>",
                                        "(Lio/flutter/view/TextureRegistry;J)V");
    map_surface_id = env->GetMethodID(map_surface_class, "id", "()J");
    map_surface_resize = env->GetMethodID(map_surface_class, "resize",
                                          "(II)Landroid/view/Surface;");
    map_surface_release = env->GetMethodID(map_surface_class, "release", "()V");
    map_surface_push =
        env->GetMethodID(map_surface_class, "push", "(Landroid/media/Image;)V");
    map_surface_close_image = env->GetMethodID(
        map_surface_class, "closeImage", "(Landroid/media/Image;)V");
    map_surface_release_readers =
        env->GetMethodID(map_surface_class, "releaseReaders", "()V");
  }
  {
    const char* path = env->GetStringUTFChars(cache_dir, nullptr);
    std::lock_guard lock(cache_dir_mutex);
    map_texture::cache_dir = path;
    env->ReleaseStringUTFChars(cache_dir, path);
  }
  // Once per process; later calls return MLN_STATUS_OK at once. The
  // application context outlives every activity.
  mln_status status = mln_android_init(env, nullptr, context);
  if (status != MLN_STATUS_OK) {
    const char* detail = mln_thread_last_error_message();
    LOGE("mln_android_init failed with status %d: %s", static_cast<int>(status),
         detail != nullptr ? detail : "");
  }
  std::lock_guard lock(registries_mutex);
  int64_t token = next_token++;
  Registries()[token] = env->NewGlobalRef(registry);
  return static_cast<jlong>(token);
}

// The engine of `token` detached the plugin: removes its registry and releases
// the maps that Dart in that engine created and didn't dispose (design D157).
JNIEXPORT void JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapigradePlugin_nativeDetach(
    JNIEnv* env, jobject, jlong token) {
  using namespace map_texture;
  {
    std::lock_guard lock(registries_mutex);
    auto it = Registries().find(token);
    if (it != Registries().end()) {
      env->DeleteGlobalRef(it->second);
      Registries().erase(it);
    }
  }
  DisposeEngineMaps(token);
}

JNIEXPORT void JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapigradePlugin_nativeSetPaused(
    JNIEnv*, jobject, jboolean paused) {
  map_texture::SetAllPaused(paused);
}

JNIEXPORT void JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapigradePlugin_nativeReduceMemoryUse(
    JNIEnv*, jobject) {
  map_texture::ReduceAllMemoryUse();
}

JNIEXPORT void JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapigradePlugin_nativeSetReadersReleased(
    JNIEnv*, jobject, jboolean released) {
  map_texture::SetReadersReleased(released);
}

JNIEXPORT jboolean JNICALL
Java_com_greensopinion_flutter_1mapigrade_MapSurface_nativeFrameImage(
    JNIEnv* env, jobject, jlong target, jlong frame_id, jobject image) {
  return reinterpret_cast<AndroidSurfaceTarget*>(target)->OnFrameImage(
             env, static_cast<uint64_t>(frame_id), image)
             ? JNI_TRUE
             : JNI_FALSE;
}

void map_texture_trim_surfaces_for_testing(int32_t restore) {
  map_texture::SetReadersReleased(restore == 0);
}

// Measurement functions (design D58).

int32_t map_texture_process_thread_count(void) {
  DIR* tasks = opendir("/proc/self/task");
  if (tasks == nullptr) return -1;
  int32_t count = 0;
  while (dirent* entry = readdir(tasks)) {
    if (entry->d_name[0] != '.') ++count;
  }
  closedir(tasks);
  return count;
}

// The process's proportional set size (PSS).
int64_t map_texture_memory_footprint(void) {
  FILE* file = std::fopen("/proc/self/smaps_rollup", "r");
  if (file == nullptr) return -1;
  char line[256];
  int64_t pss_kb = -1;
  while (std::fgets(line, sizeof(line), file) != nullptr) {
    long long value = 0;
    if (std::sscanf(line, "Pss: %lld kB", &value) == 1) {
      pss_kb = value;
      break;
    }
  }
  std::fclose(file);
  return pss_kb < 0 ? -1 : pss_kb * 1024;
}

// AThermal_getCurrentThermalStatus (API level 30) mapped to the scale of
// NSProcessInfoThermalState: none 0; light and moderate 1; severe 2; critical,
// emergency and shutdown 3. -1 on API level 29.
int32_t map_texture_thermal_state(void) {
  using Acquire = void* (*)();
  using Status = int (*)(void*);
  static void* manager = [] () -> void* {
    void* library = dlopen("libandroid.so", RTLD_NOW);
    if (library == nullptr) return nullptr;
    auto acquire =
        reinterpret_cast<Acquire>(dlsym(library, "AThermal_acquireManager"));
    return acquire != nullptr ? acquire() : nullptr;
  }();
  static auto status = reinterpret_cast<Status>(
      dlsym(RTLD_DEFAULT, "AThermal_getCurrentThermalStatus"));
  if (manager == nullptr || status == nullptr) return -1;
  int value = status(manager);
  if (value < 0) return -1;
  if (value == 0) return 0;
  if (value <= 2) return 1;
  if (value == 3) return 2;
  return 3;
}

// The plugin owns no display buffers on Android.
int32_t map_texture_released_buffers_alive_for_testing(int64_t* out_bytes) {
  if (out_bytes != nullptr) *out_bytes = 0;
  return 0;
}

int32_t map_texture_released_buffers_for_testing(int32_t reset) { return 0; }

}  // extern "C"
