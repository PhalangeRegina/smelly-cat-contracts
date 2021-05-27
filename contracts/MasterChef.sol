// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./math/SafeMath.sol";
import "./token/BEP20/IBEP20.sol";
import "./token/BEP20/SafeBEP20.sol";
import "./access/Ownable.sol";

import "./token/Pussy.sol";

// MasterChef is the master of Pussy. He can make Pussy and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once PUSSY is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PUSSYs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPussyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPussyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. PUSSYs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that PUSSYs distribution occurs.
        uint256 accPussyPerShare;   // Accumulated PUSSYs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The PUSSY TOKEN!
    Pussy public pussy;
    // Dev address.
    address public devaddr;
    // PUSSY tokens created per block.
    uint256 public pussyPerBlock;
    // Bonus muliplier for early PUSSY makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when PUSSY mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Pussy _pussy,
        address _devaddr,
        address _feeAddress,
        IBEP20 _pussyMaticLp,
        IBEP20 _pussyUsdcLp,
        uint256 _pussyPerBlock,
        uint256 _startBlock
    ) public {
        pussy = _pussy;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        pussyPerBlock = _pussyPerBlock;
        startBlock = _startBlock;

        add(2500, _pussy, 0, true);
        add(5000, _pussyMaticLp, 0, true);
        add(5000, _pussyUsdcLp, 0, true);//
        add(400, BEP20(0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d), 400, true); // ETH - USDC
        add(600, BEP20(0x6e7a5FAFcec6BB1e78bAE2A1F0B612012BF14827), 400, true); // MATIC - USDC
        add(600, BEP20(0xadbF1854e5883eB8aa7BAf50705338739e558E5b), 400, true); // MATIC - ETH
        add(600, BEP20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), 400, true); // MATIC
        add(200, BEP20(0xD6DF932A45C0f255f85145f286eA0b292B21C90B), 400, true); // AAVE
        add(200, BEP20(0x8a953cfe442c5e8855cc6c61b1293fa648bae472), 400, true); // PolyDoge
        add(200, BEP20(0x3a3Df212b7AA91Aa0402B9035b098891d276572B), 400, true); // FISH
        add(200, BEP20(0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39), 400, true); // LINK
        add(200, BEP20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619), 400, true); // WETH
        add(500, BEP20(0x831753DD7087CaC61aB5644b308642cc1c33Dc13), 400, true); // QUICK
        add(200, BEP20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063), 400, true); // DAI
        add(400, BEP20(0x2791bca1f2de4661ed88a30c99a7a9449aa84174), 400, true); // USDC
        add(200, BEP20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F), 400, true); // USDT
        add(400, BEP20(0x264e6BC3f95633725658e4D9640f7F7D9100F6AC), 400, true); // PDOGE - MATIC
        add(600, BEP20(0x019ba0325f1988213D448b3472fA1cf8D07618d7), 400, true); // QUICK - MATIC
        add(400, BEP20(0x1F1E4c845183EF6d50E9609F16f6f9cAE43BC9Cb), 400, true); // QUICK - USDC
        add(500, BEP20(0xdC9232E2Df177d7a12FdFf6EcBAb114E2231198D), 400, true); // WBTC - ETH
        add(500, BEP20(0xf04adBF75cDFc5eD26eeA4bbbb991DB002036Bdd), 400, true); // USDC - DAI
        add(400, BEP20(0x2cF7252e74036d1Da831d11089D326296e64a728), 400, true); // USDC - USDT
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 400, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accPussyPerShare: 0,
        depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's PUSSY allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 400, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending PUSSYs on frontend.
    function pendingPussy(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPussyPerShare = pool.accPussyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 pussyReward = multiplier.mul(pussyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accPussyPerShare = accPussyPerShare.add(pussyReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accPussyPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 pussyReward = multiplier.mul(pussyPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pussy.mint(devaddr, pussyReward.div(10));
        pussy.mint(address(this), pussyReward);
        pool.accPussyPerShare = pool.accPussyPerShare.add(pussyReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for PUSSY allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPussyPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safePussyTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accPussyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPussyPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safePussyTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPussyPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe gaj transfer function, just in case if rounding error causes pool to not have enough PUSSYs.
    function safePussyTransfer(address _to, uint256 _amount) internal {
        uint256 pussyBal = pussy.balanceOf(address(this));
        if (_amount > pussyBal) {
            pussy.transfer(_to, pussyBal);
        } else {
            pussy.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public{
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _pussyPerBlock) public onlyOwner {
        massUpdatePools();
        pussyPerBlock = _pussyPerBlock;
    }

    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
    }
}