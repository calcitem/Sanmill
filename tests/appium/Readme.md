# How to Test

## Environment configuration

### Install Node.js

Download and install [Node.js](https://nodejs.org).

### Install the dependencies

```shell
npm install -g appium
npm install -g appium-flutter-driver
npm install -g appium-flutter-finder
npm install -g cjs
npm install -g wd
npm install -g webdriverio
```

## Test

### Run Appium server

```shell
appium --base-path /
```

### Build debug apk

```shell
cd src/ui/flutter_app
flutter build apk --debug -v
```

### Start testing

```shell
cd tests/appium
npm start
```

### Known issues

You need to modify app's path in the test.js.

## Reference

[Getting Started - Appium](http://appium.io/docs/en/about-appium/getting-started)
[GitHub - appium-flutter-driver](https://github.com/appium-userland/appium-flutter-driver)
