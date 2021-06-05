pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/utils/Counters.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.4/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/utils/EnumerableSet.sol";


contract NFTMarketplace is ERC721, Ownable, ReentrancyGuard {

    using EnumerableSet for EnumerableSet.AddressSet;

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    mapping (uint256 => uint256) private _tokenNftIDs;

    mapping (address => uint256) public accumulatedRewardPerWallet;

    mapping (address => uint256) public rewardWeightPerWallet;

    EnumerableSet.AddressSet private allHolders;

    uint256 public allRewardsWeight;

    address burnAddress;

    address ownerAddress;

    IERC20 purchaseToken = IERC20(0x22Fa6143B3e8cd8c928F77A9326f1300ADc7b4d7);

    uint256 public burnPct;

    uint256 public artistFeePct;

    uint256 public redistributionPct;

    struct Nft {
        string uri; // points to relevant json not unique per person, NFT is unique but metadata and image are not.
        string description; // nft description
        bool mintable; // ensures the nft is mintable before allowing it to be minted.  This allows NFT minting to be disabled for a variety of reasons.
        uint256 purchaseTokenAmount; // 18 decimal places for core tokens.
        uint256 purchaseTokenAmountMultiplier; //
        uint256 mintCap; // how many Nfts can be minted for this particular NFT.  0 = infinite.
        uint256 numberMinted; // How many of this NFT have been minted so far.  Cannot exceed mintCap.
        address admin; // admin account who can manage the NFT
        address artistFeeAddress; // additional fee for artists or contest participant
        uint256 rewardWeight; // weight for on buy redistribution
    }

    Nft[] public nfts; // array of all NFTs available for purchase

    constructor() public ERC721("SmellyCat NFTs", "SCNFT") {

        // Prod Contracts
        burnAddress = address(0x000000000000000000000000000000000000dEaD);
        ownerAddress = address(0x15eA5d224c356243938FbC0C2d9Fad555c11466d);
        burnPct = 5000;
        artistFeePct = 500;
        redistributionPct = 4000;
        allRewardsWeight = 1;
    }

    // Add new NFTs
    function addNft(
        string memory uri,
        string memory description,
        bool mintable,
        uint256 purchaseTokenAmount,
        uint256 purchaseTokenAmountMultiplier,
        uint256 mintCap,
        address admin,
        address artistFeeAddress,
        uint256 rewardWeight) external onlyOwner() {
        nfts.push(Nft({
        uri: uri,
        description: description,
        mintable: mintable,
        purchaseTokenAmount: purchaseTokenAmount, // remember this includes decimals, 1e18 in most cases, but could be 1e9 or others if we add future tokens.
        purchaseTokenAmountMultiplier: purchaseTokenAmountMultiplier,
        mintCap: mintCap,
        numberMinted: 0,
        admin: admin,
        artistFeeAddress: artistFeeAddress,
        rewardWeight: rewardWeight
        }));
    }

    // Get NFT data
    function getNftData(uint256 nftID) external view returns (Nft memory) {
        require(nftID <= nfts.length-1, "getNftData:: NFT does not exist");
        return nfts[nftID];
    }

    // URI cannot be updated in this case, as it would break functionality.  If new metadata needs to be provided, add a new NFT and make the old unmintable.
    function updateNft(
        uint256 nftID,
        string memory description,
        bool mintable,
        uint256 purchaseTokenAmount,
        uint256 purchaseTokenAmountMultiplier,
        address admin,
        address artistFeeAddress,
        uint256 rewardWeight) external returns (bool) {
        Nft storage nft = nfts[nftID];
        require(address(nft.admin) == address(msg.sender) || address(msg.sender) == address(this.owner()), "updateNft:: Must be owner or admin to modify NFT");
        nft.description = description;
        nft.mintable = mintable;
        nft.purchaseTokenAmount = purchaseTokenAmount; // remember this includes decimals, 1e18 in most cases, but could be 1e9 or others if we add future tokens.
        nft.purchaseTokenAmountMultiplier = purchaseTokenAmountMultiplier;
        nft.admin = admin;
        nft.artistFeeAddress = artistFeeAddress;
        nft.rewardWeight = rewardWeight;
    }

    // Purchase NFT including minting.  Ensure Approval / Allowance to use tokens to purchase NFTs.
    function purchaseNft(uint256 nftID) external nonReentrant returns (bool) {
        require(nftID <= nfts.length-1, "PurchaseNft:: NFT Does not exist");

        Nft storage nft = nfts[nftID];

        require(nft.mintable, "PurchaseNft:: NFT is not Mintable");
        require(nft.numberMinted < nft.mintCap, "PurchaseNft:: NFT has already hit the mint cap, unable to mint more");

        uint256 price = nft.purchaseTokenAmountMultiplier.mul(nft.numberMinted).add(nft.purchaseTokenAmount);

        require(purchaseToken.balanceOf(msg.sender) >= price, "PurchaseNft:: Not enough tokens to make purchase");

        if (price > 0) {
            uint256 artistFeeAmount = price.mul(artistFeePct).div(10000) ;
            uint256 redistributionAmount = price.mul(redistributionPct).div(10000) ;
            uint256 burnAmount = price.mul(burnPct).div(10000) ;

            // Ensure an approval is done here.
            require(price - artistFeeAmount - burnAmount - redistributionAmount >= 0, "PurchaseNft:: Fees grater then total price");

            purchaseToken.transferFrom(msg.sender, address(this), price - artistFeeAmount - burnAmount); // Transfer tokens from sender to contract, external fees WILL apply, so be careful with distribution
            purchaseToken.transferFrom(msg.sender, nft.artistFeeAddress, artistFeeAmount); // Transfer tokens from sender to contract, external fees WILL apply, so be careful with distribution
            purchaseToken.transferFrom(msg.sender, burnAddress, burnAmount); // Transfer tokens from sender to contract, external fees WILL apply, so be careful with distribution

            for (uint256 i = 0; i < allHolders.length(); i++){
                address next = allHolders.at(i);
                accumulatedRewardPerWallet[next] += rewardWeightPerWallet[next].mul(redistributionAmount).mul(99).div(100).div(allRewardsWeight); //calculating in the burn tax
            }
        }

        mintNFT(nft.uri, nftID);

        nft.numberMinted += 1;
        if (nft.numberMinted == nft.mintCap){
            nft.mintable = false;
        }
        return true;
    }

    // View function to see pending PUSSYs on frontend.
    function pendingPussy(address wallet) external view returns (uint256) {
        return accumulatedRewardPerWallet[wallet];
    }

    function totalAccumulated() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < allHolders.length(); i++){
            address next = allHolders.at(i);
            total += accumulatedRewardPerWallet[next];
        }
        return total;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(address wallet) public nonReentrant {
        require(accumulatedRewardPerWallet[wallet] != 0, "No reward to withdraw");
        purchaseToken.transfer(wallet, accumulatedRewardPerWallet[wallet]);
        accumulatedRewardPerWallet[wallet] = 0;
    }

    function withdrawOwner(uint256 amount) public nonReentrant onlyOwner {
        purchaseToken.transfer(ownerAddress, amount);
    }

    // mint NFT on purchase.
    function mintNFT(string memory _tokenURI, uint256 _nftID) internal returns (uint256)
    {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _setTokenNftID(newItemId, _nftID); // Set nftID internally to NFT so it can determine which NFT the tokenID represents.
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, _tokenURI);
        return newItemId;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId) internal virtual override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId);

        Nft storage nft = nfts[_tokenNftIDs[tokenId]];

        if (from == address(0)) {
            allRewardsWeight += nft.rewardWeight;
        } else {
            rewardWeightPerWallet[from] -= nft.rewardWeight;
            if (rewardWeightPerWallet[from] == 0) {
                allHolders.remove(from);
            }
        }

        if (to == address(0)) {
            allRewardsWeight -= nft.rewardWeight;
        } else {
            rewardWeightPerWallet[to] += nft.rewardWeight;
            allHolders.add(to);
        }

    }

    // Custom function to set the nftID on the NFT when minted only.
    function _setTokenNftID(uint256 tokenID, uint256 nftID) internal virtual {
        _tokenNftIDs[tokenID] = nftID;
    }

    function tokenNftID(uint256 tokenID) external view returns (uint256) {
        require(_exists(tokenID), "tokenNftID:: Token has not been minted yet");
        return _tokenNftIDs[tokenID];
    }

    //get tokens balance on contract
    function getTokenBalance() public view returns (uint256) {
        return purchaseToken.balanceOf(address(this));
    }

    function setArtistFeePct(uint256 _artistFeePct) public onlyOwner {
        artistFeePct = _artistFeePct;
    }

    function setRedistributionPct(uint256 _redistributionPct) public onlyOwner {
        redistributionPct = _redistributionPct;
    }

    function setBurnPct(uint256 _burnPct) public onlyOwner {
        burnPct = _burnPct;
    }

    function getHolderAt(uint256 at) public onlyOwner view returns (address)  {
        return allHolders.at(at);
    }

    function getRewardWeightPerWallet(address wallet) public onlyOwner view returns (uint256)  {
        return rewardWeightPerWallet[wallet];
    }

    function getNumberOfNftsOwned(uint256 nftId, address wallet) public view returns (uint256)  {
        uint256 total = balanceOf(wallet);
        uint256 owned = 0;

        for (uint256 i = 0; i < total; i++) {
            uint256 next = tokenOfOwnerByIndex(wallet, i);
            uint256 id = _tokenNftIDs[next];
            if (id == nftId) {
                owned += 1;
            }
        }
        return owned;
    }
}