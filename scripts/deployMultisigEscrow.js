// scripts/deployMultisigEscrow.js
// Deploy MultisigRentEscrow.sol using ethers.js

const { ethers } = require("hardhat");

async function main() {
  const MultisigRentEscrow = await ethers.getContractFactory("MultisigRentEscrow");
  const escrow = await MultisigRentEscrow.deploy();
  await escrow.deployed();
  console.log("MultisigRentEscrow deployed to:", escrow.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
