const wdio = require('webdriverio');
const assert = require('assert');
const find = require('appium-flutter-finder');
const { compileFunction } = require('vm');

const opts = {
  port: 4723,
  capabilities: {
    deviceName: "PIXEL 5",
    platformName: "Android",
    platformVersion: "12",
    app: "D:\\repos\\Sanmill\\src\\ui\\flutter_app\\build\\app\\outputs\\flutter-apk\\app-debug.apk",
    automationName: "Flutter"
  }
};

(async () => {
  const driver = await wdio.remote(opts);
  await driver.elementClick(find.byValueKey('infoButton'));
  await driver.elementClick(find.byValueKey('infoDialogOkButton'));
})();
