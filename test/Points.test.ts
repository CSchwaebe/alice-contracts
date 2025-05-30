const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Points", function () {
    let Points;
    let points;
    let owner;
    let alice;
    let bob;
    const POINTS_PER_S = 5000;
    const MIN_DEPOSIT = ethers.parseEther("0.1");
    const MAX_POINTS = 5_000_000_000;

    beforeEach(async function () {
        [owner, alice, bob] = await ethers.getSigners();
        Points = await ethers.getContractFactory("Points");
        points = await Points.deploy();
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await points.owner()).to.equal(owner.address);
        });

        it("Should start with 0 total points", async function () {
            expect(await points.totalPointsIssued()).to.equal(0);
        });
    });

    describe("Deposits", function () {
        it("Should award correct points for exact S amounts", async function () {
            // 1 S = 5000 points
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            expect(await points.getPoints(alice.address)).to.equal(5000);
        });

        it("Should award correct points for fractional S amounts", async function () {
            // 1.5 S = 7500 points
            await points.connect(alice).deposit({ value: ethers.parseEther("1.5") });
            expect(await points.getPoints(alice.address)).to.equal(7500);
        });

        it("Should fail for deposits below minimum", async function () {
            await expect(
                points.connect(alice).deposit({ value: ethers.parseEther("0.09") })
            ).to.be.revertedWithCustomError(points, "InvalidDeposit");
        });

        it("Should track total points correctly", async function () {
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            await points.connect(bob).deposit({ value: ethers.parseEther("2") });
            expect(await points.totalPointsIssued()).to.equal(15000); // 5000 + 10000
        });

        it("Should handle multiple deposits from same address", async function () {
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            expect(await points.getPoints(alice.address)).to.equal(10000);
        });
    });

    describe("DepositFor", function () {
        it("Should award points to specified recipient", async function () {
            await points.connect(alice).depositFor(bob.address, { value: ethers.parseEther("1") });
            expect(await points.getPoints(bob.address)).to.equal(5000);
            expect(await points.getPoints(alice.address)).to.equal(0);
        });

        it("Should fail for zero address recipient", async function () {
            await expect(
                points.connect(alice).depositFor(ethers.ZeroAddress, { 
                    value: ethers.parseEther("1") 
                })
            ).to.be.revertedWith("Invalid recipient");
        });
    });

    describe("Points Cap", function () {
        it("Should not allow exceeding max points", async function () {
            // Try to award more than max points
            const amount = ethers.parseEther("1000000"); // 1M S = 5B points
            await expect(
                points.connect(alice).deposit({ value: amount })
            ).to.be.revertedWithCustomError(points, "PointsCapReached");
        });

        it("Should allow reaching exactly max points", async function () {
            // 1M S = 5B points (MAX_POINTS)
            const amount = ethers.parseEther("1000000");
            // First deposit just under max
            await points.connect(alice).deposit({ value: amount.sub(ethers.parseEther("1")) });
            // Then deposit remaining amount
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            expect(await points.totalPointsIssued()).to.equal(MAX_POINTS);
        });
    });

    describe("Address Tracking", function () {
        it("Should track unique addresses correctly", async function () {
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            await points.connect(bob).deposit({ value: ethers.parseEther("1") });
            await points.connect(alice).deposit({ value: ethers.parseEther("1") }); // duplicate
            expect(await points.getAddressCount()).to.equal(2);
        });

        it("Should return correct addresses with pagination", async function () {
            // Add 3 addresses
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            await points.connect(bob).deposit({ value: ethers.parseEther("2") });
            await points.connect(owner).deposit({ value: ethers.parseEther("3") });

            const [addresses, balances] = await points.getAddressesPaginated(0, 2);
            expect(addresses.length).to.equal(2);
            expect(balances.length).to.equal(2);
            expect(addresses[0]).to.equal(alice.address);
            expect(balances[0]).to.equal(5000); // 1 S worth
        });

        it("Should fail for invalid pagination parameters", async function () {
            await expect(
                points.getAddressesPaginated(0, 1001) // MAX_PAGE_SIZE = 1000
            ).to.be.revertedWith("Invalid size");

            await expect(
                points.getAddressesPaginated(1, 1) // No addresses yet
            ).to.be.revertedWith("Invalid start");
        });
    });

    describe("Withdrawal", function () {
        it("Should allow owner to withdraw", async function () {
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            const initialBalance = await owner.getBalance();
            
            await points.withdraw();
            
            const finalBalance = await owner.getBalance();
            expect(finalBalance.gt(initialBalance)).to.be.true;
        });

        it("Should fail if non-owner tries to withdraw", async function () {
            await points.connect(alice).deposit({ value: ethers.parseEther("1") });
            await expect(
                points.connect(alice).withdraw()
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("Should fail if contract has no balance", async function () {
            await expect(
                points.withdraw()
            ).to.be.revertedWith("Nothing to withdraw");
        });
    });

    describe("Direct Transfers", function () {
        it("Should reject direct transfers", async function () {
            await expect(
                alice.sendTransaction({ 
                    to: points.address, 
                    value: ethers.parseEther("1") 
                })
            ).to.be.revertedWith("Use deposit functions");
        });
    });
}); 