import * as dotenv from 'dotenv'

dotenv.config();

import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

const {
    ALCHEMY_KEY,
    ETHERSCAN_API_KEY,
    PRIVATE_KEY_TESTNET,
    GAS_PRICE
} = process.env;

const accountsTestnet = PRIVATE_KEY_TESTNET
    ? [PRIVATE_KEY_TESTNET]
    : "remote";

const gasPrice = GAS_PRICE ? Number(GAS_PRICE) : "auto"

module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.10",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    }
                }
            }
        ]
    },
    networks: {
        hardhat: {
            gasPrice: gasPrice
        },
        localhost: {
            url: 'http://127.0.0.1:8545'
        },
        goerli: {
            url: `https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_KEY}`,
            accounts: accountsTestnet
        },
        zen: {
         url: 'https://evm-tn-m2.horizenlabs.io/ethv1',
         chainId: 1661,
         accounts: accountsTestnet,
         gasPrice: gasPrice
        },
    },
    etherscan: {
        // Your API key for Etherscan
        // Obtain one at https://etherscan.io/
        apiKey: ETHERSCAN_API_KEY
    },
    mocha: {
        timeout: 50000
    }

};
