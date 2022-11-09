import hre, { ethers } from "hardhat";
import { utils, ContractFactory } from "ethers";
const wait = async (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

function toWei(x: number) {
    return utils.parseEther(x.toString())
}

function secondsTilNextHour(now: Date) : number {
    return 3600 - now.getSeconds() - (now.getMinutes() * 60);
}

interface ContractConstructorParams {
    name: string;
    symbol: string;
}

type NFTMetadata = {
    name: string;
    symbol: string;
    baseURI: string;
    maxTotalSupply: number,
    address: string;
}

interface NftConfigType {
    [key: string]: NFTMetadata
}

async function main() {

    if (hre.network.name === "hardhat") {
        console.warn(
            "You are trying to deploy contracts to the Hardhat Network, which" +
            "gets automatically created and destroyed every time. Use the Hardhat" +
            " option '--network localhost'"
        );
    }

    const defaultParams: ContractConstructorParams = {
        name: "Mock ERC20",
        symbol: "M20",
    };

    let nftConfig: NftConfigType = {
        "Alpha": {
            name: "Alpha Token",
            symbol: "ATK",
            baseURI: "ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/",
            maxTotalSupply: 10000,
            address: ""
        },
        "Beta": {
            name: "Beta Token",
            symbol: "BTK",
            baseURI: "https://boredapeyachtclub.com/api/mutants/",
            maxTotalSupply: 19427,
            address: ""
        },
        "Gamma": {
            name: "Gamma Token",
            symbol: "GTK",
            baseURI: "ipfs://QmTDcCdt3yb6mZitzWBmQr65AW6Wska295Dg9nbEYpSUDR/",
            maxTotalSupply: 9602,
            address: ""
        }
    }

    /************************************
     *  Deploy $APE coin mock contract
     *  *********************************/
    const MockERC20: ContractFactory = await ethers.getContractFactory(
        "SimpleERC20"
    );

    const mockERC20 = await MockERC20.deploy(
        defaultParams.name,
        defaultParams.symbol
    );

    await mockERC20.deployed();
    console.log("\nMock ERC20 $APE Deployed Address: ", mockERC20.address);

    /************************************
     *  Deploy BAYC, MAYC, BAKC mock contracts
     *  *********************************/
    const NFTToken: ContractFactory = await ethers.getContractFactory(
        "SimpleERC721"
    );
    const nftList = Object.keys(nftConfig);
    for (let index = 0; index < nftList.length; index++) {
        const nftData = nftConfig[nftList[index]];
        const nftToken = await NFTToken.deploy(
            nftData.name,
            nftData.symbol,
            nftData.baseURI,
            nftData.maxTotalSupply
        );

        await nftToken.deployed();

        nftConfig[nftList[index]].address = nftToken.address;
        console.log(`${nftList[index]} Token Deployed Address: `, nftConfig[nftList[index]].address);
    }

    /************************************
     *  Deploy Staking contract
     *  *********************************/
    const ApeCoinStaking = await ethers.getContractFactory("ApeCoinStaking")
    const apeCoinStaking = await ApeCoinStaking.deploy(
        mockERC20.address,
        nftConfig[nftList[0]].address,
        nftConfig[nftList[1]].address,
        nftConfig[nftList[2]].address
    )
    await apeCoinStaking.deployed()
    console.log("ApeCoin Staking address:", apeCoinStaking.address)

    /************************************
     *  Deploy Voting contract
     *  *********************************/
    const ApeCoinStakedVoting = await ethers.getContractFactory("ApeCoinStakedVoting")
    const apeCoinStakedVoting = await ApeCoinStakedVoting.deploy(apeCoinStaking.address)
    await apeCoinStakedVoting.deployed()
    console.log("ApeCoin Staked Voting address:", apeCoinStakedVoting.address)

    /************************************
     *  Set Time Ranges for all pools for the first year with real values
     *  *********************************/

    const NINETY_ONE_DAYS_IN_SECONDS = 24 * 3600 * 91
    const NINETY_TWO_DAYS_IN_SECONDS = 24 * 3600 * 92

    const currentEthTimestamp = (await ethers.provider.getBlock('latest')).timestamp
    let now = new Date(currentEthTimestamp * 1000)

    const START_TIME = currentEthTimestamp + secondsTilNextHour(now)

    const END_FIRST_QUARTER = START_TIME + NINETY_ONE_DAYS_IN_SECONDS
    const END_SECOND_QUARTER = END_FIRST_QUARTER + NINETY_TWO_DAYS_IN_SECONDS
    const END_THIRD_QUARTER = END_SECOND_QUARTER + NINETY_ONE_DAYS_IN_SECONDS
    const END_FOURTH_QUARTER = END_THIRD_QUARTER + NINETY_ONE_DAYS_IN_SECONDS

    console.log(`\nSetting up TimeRanges...`)

    // APE COIN Pool
    let firstQuarter = await apeCoinStaking.addTimeRange(0, toWei(10_500_000), START_TIME, END_FIRST_QUARTER, 0)
    await firstQuarter.wait()
    console.log(`First Quarter from ${START_TIME} to ${END_FIRST_QUARTER} for Ape Coin Pool added...`)

    let secondQuarter = await apeCoinStaking.addTimeRange(0, toWei(9_000_000), END_FIRST_QUARTER, END_SECOND_QUARTER, 0)
    await secondQuarter.wait()
    console.log(`Second Quarter from ${END_FIRST_QUARTER} to ${END_SECOND_QUARTER} for Ape Coin Pool added...`)

    let thirdQuarter = await apeCoinStaking.addTimeRange(0, toWei(6_000_000), END_SECOND_QUARTER, END_THIRD_QUARTER, 0)
    await thirdQuarter.wait()
    console.log(`Third Quarter from ${END_SECOND_QUARTER} to ${END_THIRD_QUARTER} for Ape Coin Pool added...`)

    let fourthQuarter = await apeCoinStaking.addTimeRange(0, toWei(4_500_000), END_THIRD_QUARTER, END_FOURTH_QUARTER, 0)
    await fourthQuarter.wait()
    console.log(`Fourth Quarter from ${END_THIRD_QUARTER} to ${END_FOURTH_QUARTER} for Ape Coin Pool added...\n`)


    // BAYC Pool
    firstQuarter = await apeCoinStaking.addTimeRange(1, toWei(16_486_750), START_TIME, END_FIRST_QUARTER, toWei(10_094))
    await firstQuarter.wait()
    console.log(`First Quarter from ${START_TIME} to ${END_FIRST_QUARTER} for BAYC Pool added...`)

    secondQuarter = await apeCoinStaking.addTimeRange(1, toWei(14_131_500), END_FIRST_QUARTER, END_SECOND_QUARTER, toWei(10_094))
    await secondQuarter.wait()
    console.log(`Second Quarter from ${END_FIRST_QUARTER} to ${END_SECOND_QUARTER} for BAYC Pool added...`)

    thirdQuarter = await apeCoinStaking.addTimeRange(1, toWei(9_421_000), END_SECOND_QUARTER, END_THIRD_QUARTER, toWei(10_094))
    await thirdQuarter.wait()
    console.log(`Third Quarter from ${END_SECOND_QUARTER} to ${END_THIRD_QUARTER} for BAYC Pool added...`)

    fourthQuarter = await apeCoinStaking.addTimeRange(1, toWei(7_065_750), END_THIRD_QUARTER, END_FOURTH_QUARTER, toWei(10_094))
    await fourthQuarter.wait()
    console.log(`Fourth Quarter from ${END_THIRD_QUARTER} to ${END_FOURTH_QUARTER} for BAYC Pool added...\n`)


    // MAYC Pool
    firstQuarter = await apeCoinStaking.addTimeRange(2, toWei(6_671_000), START_TIME, END_FIRST_QUARTER, toWei(2042))
    await firstQuarter.wait()
    console.log(`First Quarter from ${START_TIME} to ${END_FIRST_QUARTER} for MAYC Pool added...`)

    secondQuarter = await apeCoinStaking.addTimeRange(2, toWei(5_718_000), END_FIRST_QUARTER, END_SECOND_QUARTER, toWei(2042))
    await secondQuarter.wait()
    console.log(`Second Quarter from ${END_FIRST_QUARTER} to ${END_SECOND_QUARTER} for MAYC Pool added...`)

    thirdQuarter = await apeCoinStaking.addTimeRange(2, toWei(3_812_000), END_SECOND_QUARTER, END_THIRD_QUARTER, toWei(2042))
    await thirdQuarter.wait()
    console.log(`Third Quarter from ${END_SECOND_QUARTER} to ${END_THIRD_QUARTER} for MAYC Pool added...`)

    fourthQuarter = await apeCoinStaking.addTimeRange(2, toWei(2_859_000), END_THIRD_QUARTER, END_FOURTH_QUARTER, toWei(2042))
    await fourthQuarter.wait()
    console.log(`Fourth Quarter from ${END_THIRD_QUARTER} to ${END_FOURTH_QUARTER} for MAYC Pool added...\n`)


    // BAKC Pool
    firstQuarter = await apeCoinStaking.addTimeRange(3, toWei(1_342_250), START_TIME, END_FIRST_QUARTER, toWei(856))
    await firstQuarter.wait()
    console.log(`First Quarter from ${START_TIME} to ${END_FIRST_QUARTER} for BAKC Pool added...`)

    secondQuarter = await apeCoinStaking.addTimeRange(3, toWei(1_150_500), END_FIRST_QUARTER, END_SECOND_QUARTER, toWei(856))
    await secondQuarter.wait()
    console.log(`Second Quarter from ${END_FIRST_QUARTER} to ${END_SECOND_QUARTER} for BAKC Pool added...`)

    thirdQuarter = await apeCoinStaking.addTimeRange(3, toWei(767_000), END_SECOND_QUARTER, END_THIRD_QUARTER, toWei(856))
    await thirdQuarter.wait()
    console.log(`Third Quarter from ${END_SECOND_QUARTER} to ${END_THIRD_QUARTER} for BAKC Pool added...`)

    fourthQuarter = await apeCoinStaking.addTimeRange(3, toWei(575_250), END_THIRD_QUARTER, END_FOURTH_QUARTER, toWei(856))
    await fourthQuarter.wait()
    console.log(`Fourth Quarter from ${END_THIRD_QUARTER} to ${END_FOURTH_QUARTER} for BAKC Pool added...\n`)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
