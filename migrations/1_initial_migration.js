const YieldLever = artifacts.require("YieldLever");

module.exports = function (deployer) {
  deployer.deploy(YieldLever);
};
