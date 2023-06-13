import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, network } from "hardhat";
import { MockErc20__factory } from "../../typechain";
import { getConfig } from "../utils/config";
import { getPriceData } from "../utils/pyth";

const BigNumber = ethers.BigNumber;
const config = getConfig();

const receiver = "0x6629eC35c8Aa279BA45Dbfb575c728d3812aE31a";
const tokensToMint = [
  {
    token: config.tokens.usdc,
    amount: "1000000",
  },
];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = (await ethers.getSigners())[0];

  for (let i = 0; i < tokensToMint.length; i++) {
    const token = MockErc20__factory.connect(tokensToMint[i].token, deployer);
    const decimals = await token.decimals();
    if (token.address === config.tokens.weth) {
      await (
        await deployer.sendTransaction({
          to: receiver,
          // Convert currency unit from ether to wei
          value: ethers.utils.parseEther(tokensToMint[i].amount),
        })
      ).wait();
    } else {
      await (await token.mint(receiver, ethers.utils.parseUnits(tokensToMint[i].amount, decimals))).wait();
    }
  }
};

export default func;
func.tags = ["MintToken"];
