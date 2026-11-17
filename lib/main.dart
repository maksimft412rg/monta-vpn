name: Build APK
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.50.0'

      - name: Remove old android
        run: rm -rf android

      - name: Create new android
        run: flutter create . --platforms=android

      - name: Install dependencies
        run: flutter pub get

      - name: Build APK (skip lint)
        run: |
          cd android
          chmod +x gradlew
          ./gradlew assembleRelease -x lintVitalAnalyzeRelease -x lintVitalRelease -x lintVitalReportRelease
          cd ..

      # ШАГ ДЛЯ ПОИСКА ФАЙЛА
      - name: Find APK file
        run: find . -name "*.apk"

      # Копируем (теперь мы знаем путь)
      - name: Copy APK
        run: |
          APK_PATH=$(find . -name "app-release*.apk" | head -n 1)
          echo "Found APK at: $APK_PATH"
          mkdir -p build/app/outputs/flutter-apk/
          cp "$APK_PATH" build/app/outputs/flutter-apk/app-release.apk

      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
