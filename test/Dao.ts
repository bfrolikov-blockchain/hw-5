import { expect } from "chai";
import { keccak256 } from "@ethersproject/keccak256";
import { toUtf8Bytes } from "@ethersproject/strings";
import { ethers } from "hardhat";
import { mine, loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Dao } from "../typechain-types";

describe("Dao", function () {

  async function deployFixture() {

    const [tokenDeployer, voter1, voter2] = await ethers.getSigners();
    const daoTokenFactory = await ethers.getContractFactory("DaoToken");
    const daoFactory = await ethers.getContractFactory("Dao");

    const daoToken = await daoTokenFactory.connect(tokenDeployer).deploy();
    const dao = await daoFactory.deploy(daoToken.address);

    const proposals = [keccak256(toUtf8Bytes("proposal1")), keccak256(toUtf8Bytes("proposal2"))];
    const voters = [voter1, voter2];
    for (let i = 0; i < 2; i++) {
      await daoToken.connect(tokenDeployer).transfer(voters[i].address, getDaoTokenAmount(30));
      await daoToken.connect(voters[i]).delegate(voters[i].address);
    }

    //Needed to make sure that getPastVotes returns correct amount
    mine();

    for (let i = 0; i < 2; i++) {
      await dao.createProposal(proposals[i]);
    }

    return { tokenDeployer, voters, proposals, daoToken, dao };
  }

  async function awaitNoEvent(dao: Dao, t: Promise<any>): Promise<any> {
    await expect(t)
      .not.to.emit(dao, "ProposalAccepted")
      .not.to.emit(dao, "ProposalRejected")
      .not.to.emit(dao, "ProposalDiscarded");
  }

  it("Should not create existing proposal", async function () {
    const { proposals, dao } = await loadFixture(deployFixture);
    await expect(dao.createProposal(proposals[0]))
      .to.be.reverted;
  });

  it("Should accept proposal", async function () {
    const { voters, proposals, dao } = await loadFixture(deployFixture);

    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], true));

    await expect(dao.connect(voters[1]).vote(proposals[0], true))
      .to.emit(dao, "ProposalAccepted").withArgs(proposals[0]);
  });

  it("Should reject proposal", async function () {
    const { voters, proposals, dao } = await loadFixture(deployFixture);
    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], false));

    await expect(dao.connect(voters[1]).vote(proposals[0], false))
      .to.emit(dao, "ProposalRejected").withArgs(proposals[0]);
  });

  it("Should forget accepted/rejeced proposals", async function () {
    const { voters, proposals, dao } = await loadFixture(deployFixture);

    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], true));
    await expect(dao.connect(voters[1]).vote(proposals[0], true))
      .to.emit(dao, "ProposalAccepted").withArgs(proposals[0]);

    await dao.createProposal(proposals[0]);
    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], false));
    await expect(dao.connect(voters[1]).vote(proposals[0], false))
      .to.emit(dao, "ProposalRejected").withArgs(proposals[0]);
  });

  it("Should not affect proposals with not enough votes", async function () {
    const { voters, proposals, dao } = await loadFixture(deployFixture);

    const vote = async function () {
      await dao.connect(voters[0]).vote(proposals[0], true);
      return dao.connect(voters[1]).vote(proposals[1], false);
    }
    await awaitNoEvent(dao, vote());
  });

  it("Should be able to change vote side with a lesser vote amount", async function () {
    const { tokenDeployer, daoToken, voters, proposals, dao } = await loadFixture(deployFixture);
    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], false));
    await daoToken.connect(voters[0]).transfer(tokenDeployer.address, getDaoTokenAmount(10));
    await daoToken.connect(voters[0]).delegate(voters[0].address);
    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], true));
    await daoToken.connect(voters[1]).delegate(voters[1].address);
    await expect(dao.connect(voters[1]).vote(proposals[0], true))
      .to.emit(dao, "ProposalAccepted").withArgs(proposals[0]);
  });

  it("Should not be able to increase vote amount", async function () {
    const { tokenDeployer, daoToken, voters, proposals, dao } = await loadFixture(deployFixture);
    await awaitNoEvent(dao, dao.connect(voters[0]).vote(proposals[0], false));
    await daoToken.connect(tokenDeployer).transfer(voters[0].address, getDaoTokenAmount(30));
    await daoToken.connect(voters[0]).delegate(voters[0].address);
    await expect(dao.connect(voters[0]).vote(proposals[0], false))
      .to.be.reverted;
  })

  const ONE_DAY = 86400;

  it("Should discard expired proposals", async function () {
    const { voters, proposals, dao } = await loadFixture(deployFixture);
    await time.increase(ONE_DAY * 5);
    await expect(dao.connect(voters[0]).vote(proposals[0], false))
    .to.emit(dao, "ProposalDiscarded").withArgs(proposals[0]);
  });

  function getDaoTokenAmount(x: Number) {
    return ethers.utils.parseUnits(x.toString(), 6);
  }
});
