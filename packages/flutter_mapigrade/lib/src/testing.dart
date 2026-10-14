/// The internal types and test hooks that the test harness uses (design D69
/// of the public-api change). Not API: it may change in any version, and the
/// naming rule for exported names doesn't apply to it.
library;

export 'layer/alignment_error.dart' show AlignmentError, alignmentError;
export 'layer/camera_projection.dart' show ViewCamera, viewCameraOf;
export 'layer/map_texture_layer.dart' show MapTextureLayer;
export 'texture/map_texture_controller.dart'
    show
        FrameCamera,
        LoadingFailed,
        MapCamera,
        MapEvent,
        MapIdle,
        MapTextureController,
        MapTextureDisposedException,
        MapTextureException,
        MapTextureStats,
        RenderError,
        StyleLoaded;
export 'texture/map_texture_view.dart' show MapTextureView;
export 'texture/native_library.dart' show nativeLibraryAvailableOverride;
export 'texture/test_hooks.dart'
    show
        memoryFootprintForTesting,
        processThreadCount,
        reduceMemoryUseForTesting,
        releasedBuffersForTesting,
        resetReleasedBuffersForTesting,
        setRenderAheadForTesting,
        setRenderingPausedForTesting,
        thermalStateForTesting,
        trimSurfacesForTesting;
