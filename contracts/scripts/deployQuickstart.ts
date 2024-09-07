import { ethers } from "hardhat";

async function main() {
  // Hard-coded Oracle Address
  const oracleAddress: string = "0x68EC9556830AD097D661Df2557FBCeC166a0A075"; // Replace with your actual Oracle address

  await deployImprovedOpenAiSimpleLLM(oracleAddress);
}

async function deployImprovedOpenAiSimpleLLM(oracleAddress: string) {
  const agent = await ethers.deployContract("ImprovedOpenAiSimpleLLM", [oracleAddress], {});

  await agent.waitForDeployment();

  console.log(`ImprovedOpenAiSimpleLLM contract deployed to ${agent.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
