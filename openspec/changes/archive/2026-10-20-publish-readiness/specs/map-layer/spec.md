## MODIFIED Requirements

### Requirement: Unsupported architectures
An application that depends on the package SHALL start and run on an Android device whose process can't load the package's native library, for example because the device has none of the ABIs `arm64-v8a`, `armeabi-v7a` and `x86_64`. The package SHALL then not call native code for the life of the process. The layer SHALL offer a static property, `MapigradeLayer.isSupported`, that is true when the native library is available in the process and false otherwise, and that an application can read before it places the layer. When the native library isn't available and an application places the layer, the layer SHALL report a creation failure whose message states that the native library isn't available, as the requirement "Failure reporting" describes, and SHALL NOT throw into the application's code.

#### Scenario: App starts without the native library
- **WHEN** an application that depends on the package starts on an Android device whose process can't load the native library
- **THEN** the application starts and runs, and the package logs a warning that names the device's ABIs

#### Scenario: Application chooses another layer
- **WHEN** an application reads `MapigradeLayer.isSupported` in such a process
- **THEN** the value is false, and the application can place another layer, such as a raster tile layer, in place of `MapigradeLayer`

#### Scenario: Layer placed without the native library
- **WHEN** an application places `MapigradeLayer` with a failure handler in such a process
- **THEN** the handler receives one creation failure that states that the native library isn't available, the layer occupies the viewport without drawing anything, and the overlays after it are still drawn

#### Scenario: Supported device
- **WHEN** an application reads `MapigradeLayer.isSupported` on an Android device or emulator running the application with the ABI `arm64-v8a`, `armeabi-v7a` or `x86_64`, on an iPhone or on an Apple-silicon Mac, in an app built with the package's native library
- **THEN** the value is true
