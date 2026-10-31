# Third-party notices

EchoLoop is licensed under GNU GPL version 3 only. Third-party dependencies keep their own licenses.

## media_kit and libmpv Android libraries

EchoLoop uses the Flutter packages `media_kit`, `media_kit_video`, and `media_kit_libs_android_video`. The Android package retrieves the upstream `default-arm64-v8a` native artifact during an Android build; this source repository does not vendor that binary. The upstream project identifies the default and full flavors as MIT licensed. The notice for that flavor is reproduced here:

Copyright (c) 2016 Ilya Zhuravlev
Copyright (c) 2016 sfan5 <sfan5@live.de>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Upstream sources:

- <https://github.com/media-kit/libmpv-android-video-build>
- <https://github.com/media-kit/media-kit>
- <https://github.com/media-kit/media-kit/blob/main/libs/android/media_kit_libs_android_video/android/build.gradle>

The artifacts and their transitive components may carry additional notices. Consult the package and upstream build sources when redistributing a built APK.
