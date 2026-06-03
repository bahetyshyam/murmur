{
  "targets": [
    {
      "target_name": "hotkey",
      "sources": [ "src/hotkey.mm" ],
      "include_dirs": [ "<!@(node -p \"require('node-addon-api').include\")" ],
      "dependencies": [ "<!(node -p \"require('node-addon-api').gyp\")" ],
      "defines": [ "NAPI_VERSION=8", "NODE_ADDON_API_DISABLE_DEPRECATED" ],
      "conditions": [
        [ "OS=='mac'", {
          "xcode_settings": {
            "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
            "CLANG_CXX_LANGUAGE_DIALECT": "c++17",
            "CLANG_CXX_LIBRARY": "libc++",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "OTHER_CFLAGS": [ "-fobjc-arc" ]
          },
          "link_settings": {
            "libraries": [
              "$(SDKROOT)/System/Library/Frameworks/CoreGraphics.framework",
              "$(SDKROOT)/System/Library/Frameworks/CoreFoundation.framework",
              "$(SDKROOT)/System/Library/Frameworks/ApplicationServices.framework"
            ]
          }
        } ]
      ]
    }
  ]
}
