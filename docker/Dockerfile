FROM ubuntu:24.04 AS flutter-toolchain

ARG DEBIAN_FRONTEND=noninteractive
ARG ANDROID_COMMAND_LINE_TOOLS_VERSION=11076708
ARG ANDROID_PLATFORM=35
ARG ANDROID_BUILD_TOOLS=35.0.0
ARG ANDROID_NDK_VERSION=27.0.12077973
ARG FLUTTER_CHANNEL=stable

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.0.12077973 \
    FLUTTER_HOME=/opt/flutter \
    FLUTTER_CHANNEL=stable \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl git openjdk-17-jdk unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl --fail --location --retry 3 \
       "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_COMMAND_LINE_TOOLS_VERSION}_latest.zip" \
       --output /tmp/android-command-line-tools.zip \
    && unzip -q /tmp/android-command-line-tools.zip -d /tmp/android-tools \
    && mv /tmp/android-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm -rf /tmp/android-tools /tmp/android-command-line-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager \
       "platform-tools" \
       "platforms;android-${ANDROID_PLATFORM}" \
       "build-tools;${ANDROID_BUILD_TOOLS}" \
       "ndk;${ANDROID_NDK_VERSION}"

RUN git clone --depth 1 --branch "${FLUTTER_CHANNEL}" \
       https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && flutter precache --android \
    && flutter config --no-analytics

WORKDIR /workspace

# The target can build a mounted checkout; no app source or credentials are baked into the image.
COPY docker/build-apk.sh /usr/local/bin/build-apk
RUN chmod +x /usr/local/bin/build-apk
ENTRYPOINT ["/usr/local/bin/build-apk"]

# Optional image-build target for a source tree copied into the Docker build context.
FROM flutter-toolchain AS apk-builder
COPY . /workspace
RUN bash scripts/ensure-android-scaffold.sh \
    && flutter pub get \
    && flutter analyze \
    && flutter test \
    && flutter build apk --release
