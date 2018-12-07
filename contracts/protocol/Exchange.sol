pragma solidity >=0.4.21 <0.6.0;

import "../../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract Exchange is Ownable {
    using SafeMath for uint256;
    string constant public VERSION = "1.0.0-alpha";

    struct swapWrapper {
        uint256 _tokenAmount;
        address _owner;
    }

    struct Indexer {
        mapping(uint256 => swapWrapper) _swapWrappers;

        uint256 _indexerPos;
        uint256 _indexerLength;

        uint256 _higherPrice;
        uint256 _lowerPrice;
    }

    struct tokenWrapper {
        // General information about the token
        address _contractAddress;
        string _symbolName;

        /* We need two seperate indexes for 2 purposes: 
         *
         */
        
        mapping (uint256 => Indexer) _buyIndex;
        uint256 _currentBuyPrice;
        uint256 _lowestBuyPrice;
        uint256 _totalBuyAmount;

        mapping (uint256 => Indexer) _sellIndex;
        uint256 _currentSellPrice;
        uint256 _lowestSellPrice;
        uint256 _totalSellAmount;
    }

    mapping (uint16 => tokenWrapper) _tokens;
    uint16 _tokenSymbolIndex;

    mapping (address => uint256) _ETHBalance;
    mapping (address => mapping (uint16 => uint256)) _tokenBalance;

    // Withdrawal and Deposit ETH
    function depositETH() public payable {
        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].add(msg.value);
    }

    function withdrawETH(uint256 amountInWei) public {
        require(_ETHBalance[msg.sender] >= amountInWei);
        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].sub(amountInWei);
        msg.sender.transfer(amountInWei);
    }

    function getETHBalance() public view returns (uint256) {
        return _ETHBalance[msg.sender];
    }

    // Add new token to LoLDex
    function hasToken(string memory symbolName) public view returns (bool) {
        uint16 index = getSymbolIndex(symbolName);
        if (index == 0) {
            return false;
        }
        return true;
    }

    function addNewToken(address contractAddress, string memory symbolName) public onlyOwner {
        require(!hasToken(symbolName));
        _tokenSymbolIndex++;
        _tokens[_tokenSymbolIndex]._symbolName = symbolName;
        _tokens[_tokenSymbolIndex]._contractAddress = contractAddress;
    }

    // Withdrawal and Deposit token
    function depositToken(string memory symbolName, uint256 amount) public {
        uint16 tokenSymbolIndex = getSymbolIndexOrThrow(symbolName);
        require(_tokens[tokenSymbolIndex]._contractAddress != address(0));
        IERC20 token = IERC20(_tokens[tokenSymbolIndex]._contractAddress);
        require(token.transferFrom(msg.sender, address(this), amount) == true);
        _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].add(amount);
    }

    function withdrawToken(string memory symbolName, uint256 amount) public {
        uint16 tokenSymbolIndex = getSymbolIndexOrThrow(symbolName);
        require(_tokens[tokenSymbolIndex]._contractAddress != address(0));
        require(_tokenBalance[msg.sender][tokenSymbolIndex] >= amount);
        IERC20 token = IERC20(_tokens[tokenSymbolIndex]._contractAddress);
        _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].sub(amount);
        require(token.transfer(msg.sender, amount) == true);
    }

    function getTokenBalance(string memory symbolName) public view returns (uint256) {
        uint16 tokenSymbolIndex = getSymbolIndexOrThrow(symbolName);
        return _tokenBalance[msg.sender][tokenSymbolIndex];
    }

    // Helper functions
    function getSymbolIndex(string memory symbolName) internal returns (uint16) {
        for (uint16 i = 1; i <= _tokenSymbolIndex; i++) {
            if (stringsEqual(_tokens[i]._symbolName, symbolName)) {
                return i;
            }
        }
        return 0;
    }

    function getSymbolIndexOrThrow(string memory symbolName) internal returns (uint16) {
        uint16 index = getSymbolIndex(symbolName);
        require(index > 0);
        return index;
    }

    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        bytes memory _a = bytes(a);
        bytes memory _b = bytes(b);
        if (keccak256(_a) != keccak256(_b)) { return false; }
        return true;
    }
}
