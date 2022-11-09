// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SimpleERC721 is ERC721Enumerable {
	using Strings for string;
    using Counters for Counters.Counter; 
    uint256 public maxMint = 10;
    uint256 public maxTotalSupply;

    Counters.Counter private _tokenIds;
	string public baseURI;

    constructor(string memory name_, string memory symbol_, string memory baseURI_, uint256 _maxTotalSupply) ERC721(name_, symbol_){
        baseURI = baseURI_;
        maxTotalSupply = _maxTotalSupply;
    }

    function mint(uint256 amount) public {
        require(amount <= maxMint, "Can't mint more than 10 NFTs per tx");
        require(totalSupply() <= maxTotalSupply, "Can't exceed max total supply");

        for (uint256 index; index < amount; ++index) {
            uint256 newItemId = _tokenIds.current();
            _safeMint(_msgSender(), newItemId);
            _tokenIds.increment();
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}