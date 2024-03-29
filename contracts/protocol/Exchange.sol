pragma solidity >=0.4.21 <0.6.0;

import "../../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../node_modules/openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract Exchange is Ownable {
    using SafeMath for uint256;
    string constant public VERSION = "1.0.0-alpha";

    address public FEECONTRACTADDRESS;

    uint8 public FEEPERCENTAGE;

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
        uint256 _highestSellPrice;
        uint256 _totalSellAmount;
    }

    mapping (uint16 => tokenWrapper) _tokens;
    uint16 _tokenSymbolIndex;

    mapping (address => uint256) _ETHBalance;
    mapping (address => mapping (uint16 => uint256)) _tokenBalance;

    // Change fee contract address
    function changeFeeContractAddress(address newAddress, string memory newName) public onlyOwner {
        FEECONTRACTADDRESS = newAddress;
        _tokens[0]._contractAddress = newAddress;
        _tokens[0]._symbolName = newName;
    }

    // Change Fee percentage
    function changeFeePercentage(uint8 newPercentage) public onlyOwner {
        FEEPERCENTAGE = newPercentage;
    }

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

    // Token -> Ether
    function TokenToETH(string memory symbolName, uint256 priceInWei, uint amount) public {
        uint16 tokenSymbolIndex = getSymbolIndexOrThrow(symbolName);
        uint256 amountOfTokenAvailable = amount;
        uint256 amountOfEtherNeeded = 0;
        if(
            _tokens[tokenSymbolIndex]._totalBuyAmount == 0 //If there are no one want to trade
            || _tokens[tokenSymbolIndex]._currentBuyPrice < priceInWei // or the current price is lower than the price wanted
        ) {
            createRequestForTokenToETH(tokenSymbolIndex, priceInWei, amountOfTokenAvailable, amountOfEtherNeeded);
        } else {
            uint256 amountOfEtherAvailable = 0;
            uint256 currentPrice = _tokens[tokenSymbolIndex]._currentBuyPrice;
            uint256 currentPos;
            while(currentPrice >= priceInWei && amountOfTokenAvailable > 0) {
                currentPos = _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._indexerPos;
                while(
                    currentPos <= _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._indexerLength
                    && amountOfTokenAvailable > 0
                    ) {
                        uint256 volumeOfPrice = _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount;
                        uint256 feeAmount;
                        // Partial fulfills (token have > token want)
                        if(volumeOfPrice <= amountOfTokenAvailable) {
                            amountOfEtherAvailable = volumeOfPrice.mul(currentPrice);
                            amountOfEtherAvailable = amountOfEtherAvailable.sub(feeAmount);
                            _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].sub(volumeOfPrice);
                            _tokenBalance[_tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._owner][tokenSymbolIndex]
                                = _tokenBalance[_tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._owner][tokenSymbolIndex].add(volumeOfPrice);
                            _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount = 0;
                            _ETHBalance[msg.sender] = _ETHBalance[msg.sender].add(amountOfEtherAvailable);
                            _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._indexerPos = _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._indexerPos.add(1);
                            amountOfTokenAvailable = amountOfTokenAvailable.sub(volumeOfPrice);
                            //ETHToToken(_tokens[0]._symbolName, feeAmount, 1);
                        } else {
                            require(volumeOfPrice > amountOfTokenAvailable);
                            amountOfEtherNeeded = volumeOfPrice.mul(currentPrice);
                            amountOfEtherNeeded = amountOfEtherNeeded.sub(feeAmount);
                            _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].sub(volumeOfPrice);
                            _tokenBalance[_tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._owner][tokenSymbolIndex]
                                = _tokenBalance[_tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._owner][tokenSymbolIndex].add(volumeOfPrice);
                            _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount =
                                _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount.sub(amountOfTokenAvailable);
                            _ETHBalance[msg.sender] = _ETHBalance[msg.sender].add(amountOfEtherNeeded);
                            amountOfTokenAvailable = 0;
                            //ETHToToken(_tokens[0]._symbolName, feeAmount, 1);
                        }
                        if(
                            currentPos == _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._indexerLength
                            && _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount == 0
                            ) {
                                _tokens[tokenSymbolIndex]._totalBuyAmount = _tokens[tokenSymbolIndex]._totalBuyAmount.sub(1);
                                if(currentPrice == _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._lowerPrice || currentPrice == _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._higherPrice) {
                                    _tokens[tokenSymbolIndex]._currentBuyPrice = 0;
                                } else {
                                    _tokens[tokenSymbolIndex]._currentBuyPrice = _tokens[tokenSymbolIndex]._buyIndex[currentPrice]._lowerPrice;
                                    _tokens[tokenSymbolIndex]._buyIndex[_tokens[tokenSymbolIndex]._buyIndex[currentPrice]._lowerPrice]._higherPrice = _tokens[tokenSymbolIndex]._currentBuyPrice;
                                }

                        }
                        currentPos = currentPos.add(1);
                    }
                currentPrice = _tokens[tokenSymbolIndex]._currentBuyPrice;
            }
            if(amountOfTokenAvailable > 0) {
                createRequestForTokenToETH(tokenSymbolIndex, priceInWei, amountOfTokenAvailable, amountOfEtherNeeded);
            }
        }
    }

    function getTokenToEtherIndexer(string memory symbolName) public view returns (uint256[] memory, uint256[] memory) {
        uint16 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint256[] memory arrPricesSell = new uint256[](_tokens[tokenNameIndex]._totalSellAmount);
        uint256[] memory arrVolumesSell = new uint256[](_tokens[tokenNameIndex]._totalSellAmount);
        uint256 sellWhilePrice = _tokens[tokenNameIndex]._currentSellPrice;
        uint256 sellCounter = 0;
        if (_tokens[tokenNameIndex]._currentSellPrice > 0) {
            while (sellWhilePrice <= _tokens[tokenNameIndex]._highestSellPrice) {
                arrPricesSell[sellCounter] = sellWhilePrice;
                uint256 sellVolumeAtPrice = 0;
                uint256 sellOffersKey = 0;
                sellOffersKey = _tokens[tokenNameIndex]._sellIndex[sellWhilePrice]._indexerPos;
                while (sellOffersKey <= _tokens[tokenNameIndex]._sellIndex[sellWhilePrice]._indexerLength) {
                    sellVolumeAtPrice = sellVolumeAtPrice.add(_tokens[tokenNameIndex]._sellIndex[sellWhilePrice]._swapWrappers[sellOffersKey]._tokenAmount);
                    sellOffersKey = sellOffersKey.add(1);
                }
                arrVolumesSell[sellCounter] = sellVolumeAtPrice;
                if (_tokens[tokenNameIndex]._sellIndex[sellWhilePrice]._higherPrice == 0) {
                    break;
                }
                else {
                    sellWhilePrice = _tokens[tokenNameIndex]._sellIndex[sellWhilePrice]._higherPrice;
                }
                sellCounter = sellCounter.add(1);
            }
        }
        return (arrPricesSell, arrVolumesSell);
    }

    function getEtherToTokenIndexer(string memory symbolName) public view returns (uint256[] memory, uint256[] memory) {
        uint16 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint256[] memory arrPricesBuy = new uint256[](_tokens[tokenNameIndex]._totalBuyAmount);
        uint256[] memory arrVolumesBuy = new uint256[](_tokens[tokenNameIndex]._totalBuyAmount);
        uint256 whilePrice = _tokens[tokenNameIndex]._lowestBuyPrice;
        uint256 counter = 0;
        if (_tokens[tokenNameIndex]._currentBuyPrice > 0) {
            while (whilePrice <= _tokens[tokenNameIndex]._currentBuyPrice) {
                arrPricesBuy[counter] = whilePrice;
                uint256 buyVolumeAtPrice = 0;
                uint256 buyOffersKey = 0;

                // Obtain the Volume from Summing all Offers Mapped to a Single Price inside the Buy Order Book
                buyOffersKey = _tokens[tokenNameIndex]._buyIndex[whilePrice]._indexerPos;
                while (buyOffersKey <= _tokens[tokenNameIndex]._buyIndex[whilePrice]._indexerLength) {
                    buyVolumeAtPrice = buyVolumeAtPrice.add(_tokens[tokenNameIndex]._buyIndex[whilePrice]._swapWrappers[buyOffersKey]._tokenAmount);
                    buyOffersKey = buyOffersKey.add(1);
                }
                arrVolumesBuy[counter] = buyVolumeAtPrice;
                // Next whilePrice
                if (whilePrice == _tokens[tokenNameIndex]._buyIndex[whilePrice]._higherPrice) {
                    break;
                }
                else {
                    whilePrice = _tokens[tokenNameIndex]._buyIndex[whilePrice]._higherPrice;
                }
                counter = counter.add(1);
            }
        }
        return (arrPricesBuy, arrVolumesBuy);
    }

    // Ether -> Token
    function ETHToToken(string memory symbolName, uint256 priceInWei, uint amount) public {
        uint16 tokenSymbolIndex = getSymbolIndexOrThrow(symbolName);
        uint256 amountOfTokenNeeded = amount;
        uint256 amountOfEtherNeeded = 0;

        if(
            _tokens[tokenSymbolIndex]._totalSellAmount == 0 //If there are no one want to trade
            || _tokens[tokenSymbolIndex]._currentSellPrice > priceInWei // or the current price is higher than the price wanted
        ) {
            createRequestForETHToToken(tokenSymbolIndex, priceInWei, amountOfTokenNeeded, amountOfEtherNeeded);
        } else {
            uint256 amountOfEtherAvailable = 0;
            uint256 currentPrice = _tokens[tokenSymbolIndex]._currentSellPrice;
            uint256 currentPos;
            // TODO: based on the Token to ETH route to continue working
            while (currentPrice <= priceInWei && amountOfTokenNeeded > 0) {
                currentPos = _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._indexerPos;
                while (currentPos <= _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._indexerLength && amountOfTokenNeeded > 0) {
                    uint256 volumeAtPriceFromAddress = _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount;
                    if (volumeAtPriceFromAddress <= amountOfTokenNeeded) {
                        amountOfEtherAvailable = volumeAtPriceFromAddress.mul(currentPrice);
                        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].sub(amountOfEtherAvailable);
                        _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].add(volumeAtPriceFromAddress);
                        _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount = 0;
                        _ETHBalance[_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._owner] = _ETHBalance[_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._owner].add(amountOfEtherAvailable);
                        _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._indexerPos = _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._indexerPos.add(1);

                        amountOfTokenNeeded -= volumeAtPriceFromAddress;
                    } else {
                        require(_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount > amountOfTokenNeeded);

                        amountOfEtherNeeded = amountOfEtherNeeded.mul(currentPrice);
                        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].sub(amountOfEtherNeeded);

                        _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount = _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount.sub(amountOfTokenNeeded);
                        _ETHBalance[_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._owner] = _ETHBalance[_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._owner].add(amountOfEtherNeeded);
                        _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].add(amountOfTokenNeeded);
                        amountOfTokenNeeded = 0;
                    }
                    if (
                        currentPos == _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._indexerLength &&
                        _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._swapWrappers[currentPos]._tokenAmount == 0
                    ) {
                        _tokens[tokenSymbolIndex]._totalSellAmount = _tokens[tokenSymbolIndex]._totalSellAmount.sub(1);
                        if (currentPrice == _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._higherPrice || _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._higherPrice == 0) {
                            _tokens[tokenSymbolIndex]._currentSellPrice = 0;
                        } else {
                            _tokens[tokenSymbolIndex]._currentSellPrice = _tokens[tokenSymbolIndex]._sellIndex[currentPrice]._higherPrice;
                            _tokens[tokenSymbolIndex]._sellIndex[_tokens[tokenSymbolIndex]._sellIndex[currentPrice]._higherPrice]._lowerPrice = 0;
                        }
                    }
                    currentPos = currentPos.add(1);
                }
                currentPrice = _tokens[tokenSymbolIndex]._currentSellPrice;
            }
            if (amountOfTokenNeeded > 0) {
                createRequestForETHToToken(tokenSymbolIndex, priceInWei, amountOfTokenNeeded, amountOfEtherNeeded);
            }
        }
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

    // In case the order cannot be fulfilled at the execute moment
    function createRequestForTokenToETH(uint16 tokenSymbolIndex, uint256 priceInWei, uint256 amountOfTokenAvailable, uint256 amountOfEtherNeeded) internal {
        amountOfEtherNeeded = amountOfTokenAvailable.mul(priceInWei);
        _tokenBalance[msg.sender][tokenSymbolIndex] = _tokenBalance[msg.sender][tokenSymbolIndex].sub(amountOfTokenAvailable);

        createTokenToETHOffer(tokenSymbolIndex, priceInWei, amountOfTokenAvailable, msg.sender);
    }

    function createTokenToETHOffer(uint16 tokenSymbolIndex, uint256 priceInWei, uint256 amount, address sellerAddress) internal {
        _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._indexerLength = _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._indexerLength.add(1);
        _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._swapWrappers[_tokens[tokenSymbolIndex]._sellIndex[priceInWei]._indexerLength] = swapWrapper(amount, sellerAddress);

        if (_tokens[tokenSymbolIndex]._sellIndex[priceInWei]._indexerLength == 1) {
            _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._indexerPos = 1;
            _tokens[tokenSymbolIndex]._totalSellAmount = _tokens[tokenSymbolIndex]._totalSellAmount.add(1);
        
            uint curSellPrice = _tokens[tokenSymbolIndex]._currentSellPrice;
            uint highestSellPrice = _tokens[tokenSymbolIndex]._highestSellPrice;
            // Case 1 & 2: New Sell Offer is the First Order Entered or Highest Entry  
            if (highestSellPrice == 0 || highestSellPrice < priceInWei) {
                // Case 1: First Entry. No Sell Orders Exist `highestSellPrice == 0`. Insert New (First) Order
                if (curSellPrice == 0) {
                    _tokens[tokenSymbolIndex]._currentSellPrice = priceInWei;
                    _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._higherPrice = 0;
                    _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._lowerPrice = 0;
                // Case 2: New Sell Offer is the Highest Entry (Higher Than Highest Existing Sell Price) `highestSellPrice < priceInWei`
                } else {
                    _tokens[tokenSymbolIndex]._sellIndex[highestSellPrice]._higherPrice = priceInWei;
                    _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._lowerPrice = highestSellPrice;
                    _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._higherPrice = 0;
                }
                _tokens[tokenSymbolIndex]._highestSellPrice = priceInWei;
            }
            // Case 3: New Sell Offer is the Lowest Sell Price (First Entry). Not Need Find Right Entry Location
            else if (curSellPrice > priceInWei) {
                _tokens[tokenSymbolIndex]._sellIndex[curSellPrice]._lowerPrice = priceInWei;
                _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._higherPrice = curSellPrice;
                _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._lowerPrice = 0;
                _tokens[tokenSymbolIndex]._currentSellPrice = priceInWei;
            }
            else {
                uint sellPrice = _tokens[tokenSymbolIndex]._currentSellPrice;
                bool found = false;
                // Loop Until Find
                while (sellPrice > 0 && !found) {
                    if (
                        sellPrice < priceInWei &&
                        _tokens[tokenSymbolIndex]._sellIndex[sellPrice]._higherPrice > priceInWei
                    ) {
                        _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._lowerPrice = sellPrice;
                        _tokens[tokenSymbolIndex]._sellIndex[priceInWei]._higherPrice = _tokens[tokenSymbolIndex]._sellIndex[sellPrice]._higherPrice;
                        _tokens[tokenSymbolIndex]._sellIndex[_tokens[tokenSymbolIndex]._sellIndex[sellPrice]._higherPrice]._lowerPrice = priceInWei;
                        _tokens[tokenSymbolIndex]._sellIndex[sellPrice]._higherPrice = priceInWei;
                        // Found Location to Insert New Entry where:
                        // - Lower Sell Prices < Offer Sell Price, and 
                        // - Offer Sell Price < Entry Price
                        found = true;
                    }
                    // Set Lowest Sell Price to the Order Book's Lowest Buy Price's Higher Entry Price on Each Iteration
                    sellPrice = _tokens[tokenSymbolIndex]._sellIndex[sellPrice]._higherPrice;
                }
            }
        }
    }

    function createRequestForETHToToken(uint16 tokenSymbolIndex, uint256 priceInWei, uint256 amountOfTokenAvailable, uint256 amountOfEtherNeeded) internal {
        amountOfEtherNeeded = amountOfTokenAvailable.mul(priceInWei);
        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].sub(amountOfEtherNeeded);

        createETHToTokenOffer(tokenSymbolIndex, priceInWei, amountOfTokenAvailable, msg.sender);
    }

    function createETHToTokenOffer(uint16 tokenSymbolIndex, uint256 priceInWei, uint256 amount, address sellerAddress) internal {
        _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._indexerLength = _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._indexerLength.add(1);
        _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._swapWrappers[_tokens[tokenSymbolIndex]._buyIndex[priceInWei]._indexerLength] = swapWrapper(amount, sellerAddress);

        if (_tokens[tokenSymbolIndex]._buyIndex[priceInWei]._indexerLength == 1) {
            _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._indexerPos = 1;
            _tokens[tokenSymbolIndex]._totalBuyAmount = _tokens[tokenSymbolIndex]._totalBuyAmount.add(1);

            uint curBuyPrice = _tokens[tokenSymbolIndex]._currentBuyPrice;
            uint lowestBuyPrice = _tokens[tokenSymbolIndex]._lowestBuyPrice;

            if (lowestBuyPrice == 0 || lowestBuyPrice > priceInWei) {
                if (curBuyPrice == 0) {
                    _tokens[tokenSymbolIndex]._currentBuyPrice = priceInWei;
                    _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._higherPrice = priceInWei;
                    _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._lowerPrice = 0;
                } else {
                    _tokens[tokenSymbolIndex]._buyIndex[lowestBuyPrice]._lowerPrice = priceInWei;
                    _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._higherPrice = lowestBuyPrice;
                    _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._lowerPrice = 0;
                }
                _tokens[tokenSymbolIndex]._lowestBuyPrice = priceInWei;
            }
            // Case 3: New Buy Offer is the Highest Buy Price (Last Entry). Not Need Find Right Entry Location
            else if (curBuyPrice < priceInWei) {
                _tokens[tokenSymbolIndex]._buyIndex[curBuyPrice]._higherPrice = priceInWei;
                _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._higherPrice = priceInWei;
                _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._lowerPrice = curBuyPrice;
                _tokens[tokenSymbolIndex]._currentBuyPrice = priceInWei;
            }
            else {
                uint256 buyPrice = _tokens[tokenSymbolIndex]._currentBuyPrice;
                bool found = false;
                while (buyPrice > 0 && !found) {
                    if (
                        buyPrice < priceInWei &&
                        _tokens[tokenSymbolIndex]._buyIndex[buyPrice]._higherPrice > priceInWei
                    ) {
                        _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._lowerPrice = buyPrice;
                        _tokens[tokenSymbolIndex]._buyIndex[priceInWei]._higherPrice = _tokens[tokenSymbolIndex]._buyIndex[buyPrice]._higherPrice;
                        _tokens[tokenSymbolIndex]._buyIndex[_tokens[tokenSymbolIndex]._buyIndex[buyPrice]._higherPrice]._lowerPrice = priceInWei;
                        _tokens[tokenSymbolIndex]._buyIndex[buyPrice]._higherPrice = priceInWei;
                        found = true;
                    }
                    buyPrice = _tokens[tokenSymbolIndex]._buyIndex[buyPrice]._lowerPrice;
                }
            }
        }
    }

    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        bytes memory _a = bytes(a);
        bytes memory _b = bytes(b);
        if (keccak256(_a) != keccak256(_b)) { return false; }
        return true;
    }
}
