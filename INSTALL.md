# Project dev installation

## Prerequisites.

- macOS:   
   install [Homebrew](https://brew.sh/ru/):    
   ```bash
   brew --version || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
- Ubuntu Linux:   
  ```bash
  sudo apt install --update git libglu1-mesa google-android-platform-tools-installer
  ```

## XCode on macOS

Install XCode via App Store: [link](https://apps.apple.com/ru/app/xcode/id497799835?mt=12).

To configure the command-line tools to use the installed version of Xcode, use the following command:

```bash
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
```

Accept XCode license. Run this, enter your password, press <kbd>Enter</kbd> to read the license, type `agree`, press <kbd>Enter</kbd>

```bash
sudo xcodebuild -license
```

Run XCode. Press <kbd>⌘</kbd> <kbd>,</kbd> → **Components** → **iOS: Get**. Exit when done.

Install **cocoapods**:
```bash
brew install --formula cocoapods
```

[Настройка для разработки на iPhone](https://docs.flutter.dev/get-started/install/macos/mobile-ios#configure-your-target-ios-device)

<!--
## Google Chrome or Chromium

- macOS:
   Google Chrome, open-source edition without analytics:   
   ```bash
   brew install eloston-chromium
   echo 'export CHROME_EXECUTABLE=/Applications/Chromium.app/Contents/MacOS/Chromium' >>~/.zshrc
   . ~/.zshrc
   ```   
   **or** Google Chrome with google account and analytics:   
   ```bash
   brew install google-chrome
   ```
-->

## Android Studio

- macOS:
   ```bash
   brew install android-studio
   ```
- Ubuntu Linux: install «Android Studio» from the App Centre
- Others: see [official instructions](https://developer.android.com/studio

Run Android Studio, proceed with **Standard installation**. When done, click:   
**More actions** → **SDK Manager** → **SDK Tools** → **✅ Android SDK Command-Line Tools** → **OK** → **OK** → **Finish**. Exit Studio.

Использовать в работе Android Studio не рекомендуется из-за часто возникающих [ошибок 451](https://ru.wikipedia.org/wiki/HTTP_451)

## Flutter

Нас устроит самая свежая версия.


- macOS, Flutter latest:   
   ```bash
   brew install --cask flutter
   ```
   **Flutter installation directory** is most likely `/opt/homebrew/share/flutter` (printed in console)


- macOS, Flutter v3.44.2:   
   ```bash
   brew rm --cask flutter ; sudo rm -r /opt/flutter ; sudo mkdir -p /opt/flutter && sudo chown $(whoami) /opt/flutter
   wget https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.44.2-stable.zip -O /tmp/flutter.zip && unzip /tmp/flutter.zip -d /opt ; rm -v /tmp/flutter.zip
   echo 'export PATH="/opt/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ```   
   **Flutter installation directory** is `/opt/flutter`

- Linux, Flutter v3.44.2:   
   ```bash
   sudo chown $(whoami) /usr/src && rm -rf /usr/src/flutter; wget -O - https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.2-stable.tar.xz | tar xvJ -C /usr/src && echo 'export PATH="/usr/src/flutter/bin:$PATH"' >> ~/.bash_profile && source ~/.bash_profile
   ```   
   **Flutter installation directory** is `/usr/src/flutter`

- Others: Скачай и установи нужную версию из [Archive | Flutter](https://docs.flutter.dev/release/archive). Запомни **Flutter installation directory**


Install and configure Java **17**:

- MacOS:   
   ```bash
   brew install openjdk@17 && flutter config --jdk-dir /opt/homebrew/opt/openjdk@17
   ```
- Ubuntu Linux:   
   ```bash
   sudo apt install --update openjdk-17-jdk && flutter config --jdk-dir /usr/lib/jvm/java-17-openjdk-amd64/
   ```
- Fedora Linux:   
   ```bash
   sudo dnf install adoptium-temurin-java-repository && sudo dnf install temurin-17-jdk && flutter config --jdk-dir /usr/lib/temurin-17-ojdk/
   ```


- Others: **TODO**


Then disable analytics:

```bash
dart --disable-analytics ; flutter --disable-analytics ; flutter --disable-telemetry
```

Accept Android licenses with:   
```bash
flutter doctor --android-licenses
```

Run `flutter doctor` to ensure everything is fine:

```bash
flutter doctor
```

It should show no errors or warnings. Ignore errors for Chrome, Linux and Windows (this project
targets **Android** and **macOS** only).

See also — official manual: https://docs.flutter.dev/get-started/install

## Visual Studio Code

- macOS, open-source edition with no Microsoft analytics:   
   ```bash
   brew install --cask vscodium
   ```   
- Ubuntu Linux: install **Codium** from the Ubuntu Software Center or [download latest release .deb](https://github.com/vscodium/vscodium/releases)
- Others: see [docs](https://vscodium.com/#install)   


Then,   
1. Launch **VSCodium**. 
2. Optional: [install Russian language](https://mirsovetov.net/vs-code-language.html) если нужен русский язык.
3. Optional: [add Visual Studio Marketplace to VSCodium](https://www.flypenguin.de/2023/02/26/use-vscodium-with-microsofts-proprietary-marketplace/)
4. Click **View** → **Extensions**.
5. Search for and install **Flutter** extension
6. Click **View** → **Command Palette** (<kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>P</kbd> or <kbd>Ctrl</kbd> <kbd>Shift</kbd> <kbd>P</kbd>).
7. Search for and select **Flutter: New Project**.
8. VS Code prompts you to locate the Flutter SDK on your computer.
    - Click **Locate SDK**
    - Point the app to to **Flutter installation directory**.
9. When prompted **Which Flutter template?**, ignore it. Press <kbd>Esc</kbd>.

# Сборка и запуск:

## Подготовка Android-телефона:

- [Включите режим разработчика](https://www.android.com/intl/en_uk/articles/enable-android-developer-settings/) в системе Android.
- Подключите телефон проводом (рекомендуется USB3).
- Разрешите отладку по USB в предупреждении телефона.
- Переподключите телефон и убедитесь, что новых предупреждений нет.
- Проверьте вывод команды `flutter devices` и `adb devices`, там должен быть ваш телефон.

## В VSCodium:

1. Загрузка пакетов.

   - В «Проводнике» слева откройте `pubspec.yaml`.
   - Справа от строки вкладок, в правом верхнем углу, появится кнопка загрузки ⬇️. Нажмите её. 

2. Запуск

   - Справа снизу написано текущее устройство. Это подключенный телефон или ваша ОС на компьютере. Щёлкните туда и выберите, где запускать.
   - В «Проводнике» слева откройте `lib` → `main.dart`.
   - Справа от строки вкладок, в правом верхнем углу, появится кнопка запуска ▶️. Нажмите её. 

*После изменения и сохранения кода приложение обновится на лету.*

## В консоли:

```bash
flutter pub get ; flutter run
```

# Git-хук и CI

Перед первым коммитом установите pre-commit-хук (форматирование, `dart fix --dry-run`,
`flutter analyze`, `flutter test`):

```bash
contrib/install-hooks.sh
```

(скрипт требует, чтобы репозиторий уже был инициализирован: `git init`)

Пропустить проверки для отдельного коммита: `git commit --no-verify`.

Те же проверки выполняет GitHub Actions (`.github/workflows/flutter-workflow.yaml`): анализ,
тесты с отчётом и сборка APK; собранный APK лежит в артефактах запуска.