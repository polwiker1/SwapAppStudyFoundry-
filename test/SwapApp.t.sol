// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {SwappApp} from "../src/swappApp.sol";
import {V3LiquidityStrategy} from "../src/V3LiquidityStrategy.sol";
import {V3PriceLimitHelper} from "../src/V3PriceLimitHelper.sol";
import {V3QuoteHelper} from "../src/V3QuoteHelper.sol";
import {V3RangeHelper} from "../src/V3RangeHelper.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {ISwapRouter02} from "../src/interfaces.sol/ISwapRouter02.sol";
import {INonfungiblePositionManager} from "../src/interfaces.sol/INonfungiblePositionManager.sol";
import {IQuoterV2} from "../src/interfaces.sol/IQuoterV2.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFactory {
    mapping(address => mapping(address => address)) public getPair;

    function setPair(address tokenA, address tokenB, address pair) external {
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
    }
}

contract MockRouter {
    MockERC20 public immutable lpToken;

    constructor(address _lpToken) {
        lpToken = MockERC20(_lpToken);
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(path[path.length - 1]).mint(to, amountIn);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        MockERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        MockERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = amountA < amountB ? amountA : amountB;
        lpToken.mint(to, liquidity);
    }

    function removeLiquidity(address tokenA, address tokenB, uint256 liquidity, uint256, uint256, address to, uint256)
        external
        returns (uint256 amountA, uint256 amountB)
    {
        lpToken.transferFrom(msg.sender, address(this), liquidity);

        amountA = liquidity;
        amountB = liquidity;
        MockERC20(tokenA).mint(to, amountA);
        MockERC20(tokenB).mint(to, amountB);
    }
}

contract MockV3Factory {
    mapping(bytes32 => address) public pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        pools[_poolKey(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool) {
        pool = pools[_poolKey(tokenA, tokenB, fee)];
    }

    function _poolKey(address tokenA, address tokenB, uint24 fee) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1, fee));
    }
}

contract MockSwapRouter02 {
    function exactInputSingle(ISwapRouter02.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        require(params.amountIn >= params.amountOutMinimum, "too little received");

        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn;
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }
}

contract MockNonfungiblePositionManager {
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) public ownerOf;

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(block.timestamp <= params.deadline, "mint expired");
        require(params.tickLower < params.tickUpper, "bad ticks");

        MockERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        MockERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);

        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "mint min");

        liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
        tokenId = nextTokenId++;
        ownerOf[tokenId] = params.recipient;
    }
}

contract MockQuoterV2 {
    uint256 public quoteAmountOut = 50e18;
    uint160 public quoteSqrtPriceX96After = 1 << 96;
    uint32 public quoteInitializedTicksCrossed = 12;
    uint256 public quoteGasEstimate = 120_000;

    function setQuote(uint256 amountOut) external {
        quoteAmountOut = amountOut;
    }

    function quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams memory)
        external
        view
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountOut = quoteAmountOut;
        sqrtPriceX96After = quoteSqrtPriceX96After;
        initializedTicksCrossed = quoteInitializedTicksCrossed;
        gasEstimate = quoteGasEstimate;
    }
}

contract MockV3Pool {
    int24 public immutable tickSpacing;
    int24 public currentTick;

    constructor(int24 _tickSpacing, int24 _currentTick) {
        tickSpacing = _tickSpacing;
        currentTick = _currentTick;
    }

    function setCurrentTick(int24 tick) external {
        currentTick = tick;
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        sqrtPriceX96 = 1 << 96;
        tick = currentTick;
        observationIndex = 0;
        observationCardinality = 0;
        observationCardinalityNext = 0;
        feeProtocol = 0;
        unlocked = true;
    }
}

contract SwapAppForkArbitrumTest is Test {
    address internal constant ARBITRUM_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address internal constant ARBITRUM_V2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;
    address internal constant ARBITRUM_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant ARBITRUM_SWAP_ROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant ARBITRUM_NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint24 internal constant USDC_WETH_V3_FEE = 500;
    int24 internal constant FULL_RANGE_TICK_LOWER_500 = -887_270;
    int24 internal constant FULL_RANGE_TICK_UPPER_500 = 887_270;

    SwappApp app;
    V3LiquidityStrategy v3Strategy;
    GovernanceToken gov;

    address user = address(0xBEEF);
    address trader = address(0xA11CE);
    address treasury = address(0xCAFE);

    function setUp() external {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        gov = new GovernanceToken("Governance", "GOV");
        app = new SwappApp(ARBITRUM_V2_ROUTER, ARBITRUM_V2_FACTORY, address(gov), treasury, 10, 3000, 1e18);
        v3Strategy =
            new V3LiquidityStrategy(ARBITRUM_V3_FACTORY, ARBITRUM_SWAP_ROUTER02, ARBITRUM_NONFUNGIBLE_POSITION_MANAGER);
        gov.mint(address(app), 1_000_000e18);

        deal(USDC, user, 5_000e6);
        deal(USDC, trader, 50_000e6);
        deal(WETH, trader, 20e18);

        vm.prank(user);
        ERC20(USDC).approve(address(app), type(uint256).max);

        vm.prank(user);
        ERC20(USDC).approve(address(v3Strategy), type(uint256).max);

        vm.startPrank(trader);
        ERC20(USDC).approve(ARBITRUM_SWAP_ROUTER02, type(uint256).max);
        ERC20(WETH).approve(ARBITRUM_SWAP_ROUTER02, type(uint256).max);
        vm.stopPrank();
    }

    function test_fork_swap_on_arbitrum_router() external {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint256 amountIn = 1_000e6;
        uint256 fee = (amountIn * 10) / 10_000;

        uint256 treasuryBefore = ERC20(USDC).balanceOf(treasury);
        uint256 userWethBefore = ERC20(WETH).balanceOf(user);

        vm.prank(user);
        uint256 amountOut = app.swapTokens(amountIn, 0, path, block.timestamp + 30 minutes);

        assertEq(ERC20(USDC).balanceOf(treasury), treasuryBefore + fee);
        assertEq(ERC20(USDC).balanceOf(user), 4_000e6);
        assertGt(ERC20(WETH).balanceOf(user), userWethBefore);
        assertEq(amountOut, ERC20(WETH).balanceOf(user) - userWethBefore);
    }

    function test_fork_add_liquidity_single_token_usdc() external {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint256 amountInUSDC = 1_000e6;
        uint256 deadline = block.timestamp + 30 minutes;

        SwappApp.AddLiquiditySingleTokenUSDCParams memory p = SwappApp.AddLiquiditySingleTokenUSDCParams({
            usdc: USDC,
            tokenOther: WETH,
            amountInUSDC: amountInUSDC,
            amountOutMinSwap: 0,
            amountUSDCMinAdd: 0,
            amountTokenMinAdd: 0,
            pathUSDCToTokenOther: path,
            deadline: deadline
        });

        address lpToken = MockFactory(ARBITRUM_V2_FACTORY).getPair(USDC, WETH);
        uint256 lpBefore = ERC20(lpToken).balanceOf(user);

        vm.prank(user);
        (,, uint256 liquidity) = app.addLiquiditySingleTokenUSDC(p);

        uint256 lpAfter = ERC20(lpToken).balanceOf(user);
        assertGt(liquidity, 0);
        assertEq(lpAfter, lpBefore + liquidity);
    }

    function test_fork_v3_position_remains_active_and_collects_fees_after_swaps() external {
        V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params memory p =
            V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params({
                usdc: USDC,
                tokenOther: WETH,
                fee: USDC_WETH_V3_FEE,
                tickLower: FULL_RANGE_TICK_LOWER_500,
                tickUpper: FULL_RANGE_TICK_UPPER_500,
                amountInUSDC: 1_000e6,
                amountOutMinSwap: 0,
                amountUSDCMinMint: 0,
                amountTokenMinMint: 0,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 30 minutes
            });

        vm.prank(user);
        (uint256 tokenId, uint128 mintedLiquidity,,,) = v3Strategy.addLiquiditySingleTokenUSDCV3(p);

        assertEq(INonfungiblePositionManager(ARBITRUM_NONFUNGIBLE_POSITION_MANAGER).ownerOf(tokenId), user);
        assertGt(mintedLiquidity, 0);

        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7_200);

        _swapV3FromTrader(USDC, WETH, 20_000e6);
        _swapV3FromTrader(WETH, USDC, 5e17);

        (,,,,,,, uint128 activeLiquidity,,,,) =
            INonfungiblePositionManager(ARBITRUM_NONFUNGIBLE_POSITION_MANAGER).positions(tokenId);
        assertEq(activeLiquidity, mintedLiquidity);

        vm.prank(user);
        (uint256 amount0Collected, uint256 amount1Collected) = INonfungiblePositionManager(
                ARBITRUM_NONFUNGIBLE_POSITION_MANAGER
            )
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId, recipient: user, amount0Max: type(uint128).max, amount1Max: type(uint128).max
                })
            );

        assertGt(amount0Collected + amount1Collected, 0);
    }

    function _swapV3FromTrader(address tokenIn, address tokenOut, uint256 amountIn) internal {
        vm.prank(trader);
        ISwapRouter02(ARBITRUM_SWAP_ROUTER02)
            .exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: USDC_WETH_V3_FEE,
                    recipient: trader,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }
}

contract SwapAppTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    GovernanceToken gov;
    MockRouter router;
    MockFactory factory;
    MockERC20 lpToken;
    SwappApp app;

    address user = address(0x123);
    address treasury = address(0x999);

    function setUp() external {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        lpToken = new MockERC20("LP Token", "LP");
        gov = new GovernanceToken("Governance", "GOV");
        router = new MockRouter(address(lpToken));
        factory = new MockFactory();
        factory.setPair(address(tokenA), address(tokenB), address(lpToken));

        // 1 fee token value -> 1 GOV token (scaled 1e18)
        app = new SwappApp(address(router), address(factory), address(gov), treasury, 10, 3000, 1e18);

        tokenA.mint(user, 1_000_000e18);

        vm.prank(user);
        tokenA.approve(address(app), type(uint256).max);
    }

    function _pathAB() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
    }

    function test_swap_charges_fee_and_sends_to_treasury() external {
        gov.mint(address(app), 1_000_000e18);

        uint256 amountIn = 1000e18;
        uint256 fee = (amountIn * 10) / 10_000;

        vm.prank(user);
        uint256 amountOut = app.swapTokens(amountIn, 0, _pathAB(), block.timestamp + 1);

        assertEq(amountOut, amountIn - fee);
        assertEq(tokenA.balanceOf(treasury), fee);
        assertEq(tokenB.balanceOf(user), amountIn - fee);
    }

    function test_swap_rewards_30_percent_of_fee_in_gov_token() external {
        gov.mint(address(app), 1_000_000e18);

        uint256 amountIn = 1000e18;
        uint256 fee = (amountIn * 10) / 10_000;
        uint256 expectedReward = (fee * 3000) / 10_000;

        vm.prank(user);
        app.swapTokens(amountIn, 0, _pathAB(), block.timestamp + 1);

        assertEq(gov.balanceOf(user), expectedReward);
        assertEq(app.pendingGovRewards(user), 0);
    }

    function test_no_revert_when_insufficient_gov_and_pending_is_created() external {
        // only 0.1 GOV liquidity on app
        gov.mint(address(app), 1e17);

        uint256 amountIn = 1000e18;
        uint256 fee = (amountIn * 10) / 10_000;
        uint256 fullReward = (fee * 3000) / 10_000;

        vm.prank(user);
        app.swapTokens(amountIn, 0, _pathAB(), block.timestamp + 1);

        assertEq(gov.balanceOf(user), 1e17);
        assertEq(app.pendingGovRewards(user), fullReward - 1e17);
    }

    function test_claim_pending_rewards_partial_then_full() external {
        gov.mint(address(app), 1e17);

        uint256 amountIn = 1000e18;
        uint256 fee = (amountIn * 10) / 10_000;
        uint256 fullReward = (fee * 3000) / 10_000;

        vm.prank(user);
        app.swapTokens(amountIn, 0, _pathAB(), block.timestamp + 1);

        uint256 firstPending = fullReward - 1e17;
        assertEq(app.pendingGovRewards(user), firstPending);

        // fund only part of pending
        gov.mint(address(app), 1e17);
        vm.prank(user);
        uint256 claimed1 = app.claimPendingGovRewards();
        assertEq(claimed1, 1e17);
        assertEq(app.pendingGovRewards(user), firstPending - 1e17);

        // fund the rest and claim all
        gov.mint(address(app), firstPending - 1e17);
        vm.prank(user);
        uint256 claimed2 = app.claimPendingGovRewards();
        assertEq(claimed2, firstPending - 1e17);
        assertEq(app.pendingGovRewards(user), 0);
    }

    function test_get_amount_out_min_uses_router_quote() external view {
        uint256 amountIn = 1000e18;
        uint256 outMin = app.getAmountOutMin(amountIn, _pathAB());
        assertEq(outMin, amountIn);
    }

    function test_swap_reverts_with_bad_path() external {
        address[] memory badPath = new address[](1);
        badPath[0] = address(tokenA);

        vm.prank(user);
        vm.expectRevert("bad path");
        app.swapTokens(100e18, 0, badPath, block.timestamp + 1);
    }

    function test_claim_pending_rewards_reverts_when_no_pending() external {
        vm.prank(user);
        vm.expectRevert("no pending");
        app.claimPendingGovRewards();
    }

    function test_claim_pending_rewards_reverts_when_no_gov_liquidity() external {
        uint256 amountIn = 1000e18;

        vm.prank(user);
        app.swapTokens(amountIn, 0, _pathAB(), block.timestamp + 1);

        assertGt(app.pendingGovRewards(user), 0);

        vm.prank(user);
        vm.expectRevert("no gov liquidity");
        app.claimPendingGovRewards();
    }

    function test_set_fee_params_updates_values() external {
        app.setFeeParams(25, 5000);
        assertEq(app.feeBps(), 25);
        assertEq(app.rewardShareBps(), 5000);
    }

    function test_set_treasury_updates_value() external {
        address newTreasury = address(0xABCD);
        app.setTreasury(newTreasury);
        assertEq(app.treasury(), newTreasury);
    }

    function test_set_gov_tokens_per_fee_token_updates_value() external {
        app.setGovTokensPerFeeToken(2e18);
        assertEq(app.govTokensPerFeeToken(), 2e18);
    }

    function test_only_owner_reverts_on_setters() external {
        vm.startPrank(user);

        vm.expectRevert();
        app.setFeeParams(20, 2000);

        vm.expectRevert();
        app.setTreasury(address(0xDEAD));

        vm.expectRevert();
        app.setGovTokensPerFeeToken(9e18);

        vm.stopPrank();
    }

    function test_set_fee_params_reverts_when_out_of_bounds() external {
        vm.expectRevert("fee>bsp");
        app.setFeeParams(10_001, 100);

        vm.expectRevert("share>bsp");
        app.setFeeParams(100, 10_001);
    }

    function test_set_treasury_reverts_when_zero_address() external {
        vm.expectRevert("treasury=0");
        app.setTreasury(address(0));
    }

    function test_constructor_reverts_on_invalid_params() external {
        vm.expectRevert("router=0");
        new SwappApp(address(0), address(factory), address(gov), treasury, 10, 3000, 1e18);

        vm.expectRevert("factory=0");
        new SwappApp(address(router), address(0), address(gov), treasury, 10, 3000, 1e18);

        vm.expectRevert("gov=0");
        new SwappApp(address(router), address(factory), address(0), treasury, 10, 3000, 1e18);

        vm.expectRevert("treasury=0");
        new SwappApp(address(router), address(factory), address(gov), address(0), 10, 3000, 1e18);

        vm.expectRevert("fee>bsp");
        new SwappApp(address(router), address(factory), address(gov), treasury, 10_001, 3000, 1e18);

        vm.expectRevert("share>bsp");
        new SwappApp(address(router), address(factory), address(gov), treasury, 10, 10_001, 1e18);
    }

    function test_add_liquidity_single_token_usdc_mints_lp_to_user() external {
        SwappApp.AddLiquiditySingleTokenUSDCParams memory p = SwappApp.AddLiquiditySingleTokenUSDCParams({
            usdc: address(tokenA),
            tokenOther: address(tokenB),
            amountInUSDC: 100e18,
            amountOutMinSwap: 0,
            amountUSDCMinAdd: 0,
            amountTokenMinAdd: 0,
            pathUSDCToTokenOther: _pathAB(),
            deadline: block.timestamp + 1
        });

        uint256 userLpBefore = lpToken.balanceOf(user);
        vm.prank(user);
        (uint256 amountUSDCUsed, uint256 amountTokenUsed, uint256 liquidity) = app.addLiquiditySingleTokenUSDC(p);

        assertEq(amountUSDCUsed, 50e18);
        assertEq(amountTokenUsed, 50e18);
        assertEq(liquidity, 50e18);
        assertEq(lpToken.balanceOf(user), userLpBefore + liquidity);
    }

    function test_add_liquidity_single_token_reverts_when_deadline_expired() external {
        SwappApp.AddLiquiditySingleTokenUSDCParams memory p = SwappApp.AddLiquiditySingleTokenUSDCParams({
            usdc: address(tokenA),
            tokenOther: address(tokenB),
            amountInUSDC: 100e18,
            amountOutMinSwap: 0,
            amountUSDCMinAdd: 0,
            amountTokenMinAdd: 0,
            pathUSDCToTokenOther: _pathAB(),
            deadline: block.timestamp
        });

        vm.warp(block.timestamp + 1);
        vm.prank(user);
        vm.expectRevert("expired");
        app.addLiquiditySingleTokenUSDC(p);
    }

    function test_remove_liquidity_to_usdc_returns_single_token_to_user() external {
        SwappApp.AddLiquiditySingleTokenUSDCParams memory addP = SwappApp.AddLiquiditySingleTokenUSDCParams({
            usdc: address(tokenA),
            tokenOther: address(tokenB),
            amountInUSDC: 100e18,
            amountOutMinSwap: 0,
            amountUSDCMinAdd: 0,
            amountTokenMinAdd: 0,
            pathUSDCToTokenOther: _pathAB(),
            deadline: block.timestamp + 1
        });

        vm.prank(user);
        (,, uint256 mintedLp) = app.addLiquiditySingleTokenUSDC(addP);

        vm.prank(user);
        lpToken.approve(address(app), type(uint256).max);

        address[] memory pathBA = new address[](2);
        pathBA[0] = address(tokenB);
        pathBA[1] = address(tokenA);

        SwappApp.RemoveLiquidityToUSDCParams memory removeP = SwappApp.RemoveLiquidityToUSDCParams({
            lpToken: address(lpToken),
            usdc: address(tokenA),
            tokenOther: address(tokenB),
            liquidityToBurn: mintedLp,
            amountUSDCMinRemove: 0,
            amountTokenMinRemove: 0,
            amountOutMinSwap: 0,
            pathTokenOtherToUSDC: pathBA,
            deadline: block.timestamp + 1
        });

        uint256 userUsdcBefore = tokenA.balanceOf(user);
        vm.prank(user);
        uint256 totalUSDCOut = app.removeLiquidityToUSDC(removeP);

        assertEq(totalUSDCOut, mintedLp * 2);
        assertEq(tokenA.balanceOf(user), userUsdcBefore + totalUSDCOut);
    }
}

contract V3LiquidityStrategyTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockV3Factory factory;
    MockSwapRouter02 router;
    MockNonfungiblePositionManager positionManager;
    V3LiquidityStrategy strategy;

    address user = address(0x456);
    uint24 fee = 3000;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        factory = new MockV3Factory();
        router = new MockSwapRouter02();
        positionManager = new MockNonfungiblePositionManager();
        strategy = new V3LiquidityStrategy(address(factory), address(router), address(positionManager));

        factory.setPool(address(usdc), address(weth), fee, address(0x1000));
        usdc.mint(user, 10_000e18);

        vm.prank(user);
        usdc.approve(address(strategy), type(uint256).max);
    }

    function test_add_liquidity_single_token_usdc_v3_mints_position_to_user() external {
        V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params memory p =
            V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params({
                usdc: address(usdc),
                tokenOther: address(weth),
                fee: fee,
                tickLower: -887_220,
                tickUpper: 887_220,
                amountInUSDC: 100e18,
                amountOutMinSwap: 0,
                amountUSDCMinMint: 0,
                amountTokenMinMint: 0,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1
            });

        vm.prank(user);
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amountUSDCUsed,
            uint256 amountTokenUsed,
            uint256 tokenOtherReceived
        ) = strategy.addLiquiditySingleTokenUSDCV3(p);

        assertEq(tokenId, 1);
        assertEq(positionManager.ownerOf(tokenId), user);
        assertEq(liquidity, 50e18);
        assertEq(amountUSDCUsed, 50e18);
        assertEq(amountTokenUsed, 50e18);
        assertEq(tokenOtherReceived, 50e18);
    }

    function test_add_liquidity_single_token_usdc_v3_reverts_when_pool_missing() external {
        V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params memory p =
            V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params({
                usdc: address(usdc),
                tokenOther: address(weth),
                fee: 500,
                tickLower: -887_220,
                tickUpper: 887_220,
                amountInUSDC: 100e18,
                amountOutMinSwap: 0,
                amountUSDCMinMint: 0,
                amountTokenMinMint: 0,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1
            });

        vm.prank(user);
        vm.expectRevert("pool not found");
        strategy.addLiquiditySingleTokenUSDCV3(p);
    }

    function test_add_liquidity_single_token_usdc_v3_reverts_when_swap_min_is_too_high() external {
        V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params memory p =
            V3LiquidityStrategy.AddLiquiditySingleTokenUSDCV3Params({
                usdc: address(usdc),
                tokenOther: address(weth),
                fee: fee,
                tickLower: -887_220,
                tickUpper: 887_220,
                amountInUSDC: 100e18,
                amountOutMinSwap: 51e18,
                amountUSDCMinMint: 0,
                amountTokenMinMint: 0,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1
            });

        vm.prank(user);
        vm.expectRevert("too little received");
        strategy.addLiquiditySingleTokenUSDCV3(p);
    }
}

contract V3QuoteHelperTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockQuoterV2 quoter;
    V3QuoteHelper helper;

    uint24 fee = 3000;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        quoter = new MockQuoterV2();
        helper = new V3QuoteHelper(address(quoter));
    }

    function test_preview_single_token_usdc_v3_calculates_minimums_from_slippage() external {
        V3QuoteHelper.SingleTokenV3Preview memory preview = helper.previewSingleTokenUSDCV3(
            V3QuoteHelper.SingleTokenV3PreviewParams({
                usdc: address(usdc),
                tokenOther: address(weth),
                fee: fee,
                amountInUSDC: 100e18,
                slippageBps: 100,
                sqrtPriceLimitX96: 0
            })
        );

        assertEq(preview.amountToSwap, 50e18);
        assertEq(preview.usdcForLiquidity, 50e18);
        assertEq(preview.expectedTokenOther, 50e18);
        assertEq(preview.amountOutMinSwap, 49.5e18);
        assertEq(preview.amountUSDCMinMint, 49.5e18);
        assertEq(preview.amountTokenMinMint, 49.5e18);
        assertEq(preview.sqrtPriceX96After, 1 << 96);
        assertEq(preview.initializedTicksCrossed, 12);
        assertEq(preview.gasEstimate, 120_000);
    }

    function test_preview_single_token_usdc_v3_reverts_when_slippage_is_too_high() external {
        vm.expectRevert("slippage>bsp");
        helper.previewSingleTokenUSDCV3(
            V3QuoteHelper.SingleTokenV3PreviewParams({
                usdc: address(usdc),
                tokenOther: address(weth),
                fee: fee,
                amountInUSDC: 100e18,
                slippageBps: 10_001,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function test_constructor_reverts_when_quoter_is_zero() external {
        vm.expectRevert("quoter=0");
        new V3QuoteHelper(address(0));
    }
}

contract V3RangeHelperTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockV3Factory factory;
    MockV3Pool pool;
    V3RangeHelper helper;

    uint24 fee = 500;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        factory = new MockV3Factory();
        pool = new MockV3Pool(10, 203_456);
        helper = new V3RangeHelper(address(factory));

        factory.setPool(address(usdc), address(weth), fee, address(pool));
    }

    function test_preview_range_returns_low_medium_high_exposure_ranges() external view {
        V3RangeHelper.RangePreview memory low =
            helper.previewRange(address(usdc), address(weth), fee, V3RangeHelper.ExposureMode.Low);
        V3RangeHelper.RangePreview memory medium =
            helper.previewRange(address(usdc), address(weth), fee, V3RangeHelper.ExposureMode.Medium);
        V3RangeHelper.RangePreview memory high =
            helper.previewRange(address(usdc), address(weth), fee, V3RangeHelper.ExposureMode.High);

        assertEq(low.pool, address(pool));
        assertEq(low.currentTick, 203_456);
        assertEq(low.tickSpacing, 10);

        assertEq(low.tickLower, 193_450);
        assertEq(low.tickUpper, 213_450);
        assertEq(medium.tickLower, 200_450);
        assertEq(medium.tickUpper, 206_450);
        assertEq(high.tickLower, 202_650);
        assertEq(high.tickUpper, 204_250);

        assertGt(low.tickUpper - low.tickLower, medium.tickUpper - medium.tickLower);
        assertGt(medium.tickUpper - medium.tickLower, high.tickUpper - high.tickLower);
    }

    function test_preview_range_floors_negative_ticks_to_spacing() external {
        pool.setCurrentTick(-203_456);

        V3RangeHelper.RangePreview memory high =
            helper.previewRange(address(usdc), address(weth), fee, V3RangeHelper.ExposureMode.High);

        assertEq(high.tickLower, -204_260);
        assertEq(high.tickUpper, -202_660);
    }

    function test_preview_range_reverts_when_pool_missing() external {
        vm.expectRevert("pool not found");
        helper.previewRange(address(usdc), address(weth), 3000, V3RangeHelper.ExposureMode.Medium);
    }
}

contract V3PriceLimitHelperTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockV3Factory factory;
    MockV3Pool pool;
    V3PriceLimitHelper helper;

    uint24 fee = 500;

    function setUp() external {
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        factory = new MockV3Factory();
        pool = new MockV3Pool(10, 200_000);
        helper = new V3PriceLimitHelper(address(factory));

        factory.setPool(address(usdc), address(weth), fee, address(pool));
    }

    function test_preview_sqrt_price_limit_sets_limit_tick_by_swap_direction() external view {
        V3PriceLimitHelper.PriceLimitPreview memory preview =
            helper.previewSqrtPriceLimitX96(address(usdc), address(weth), fee, 100);

        assertEq(preview.pool, address(pool));
        assertEq(preview.currentTick, 200_000);
        assertEq(preview.sqrtPriceLimitX96 > 0, true);

        if (address(usdc) < address(weth)) {
            assertEq(preview.zeroForOne, true);
            assertEq(preview.limitTick, 199_900);
        } else {
            assertEq(preview.zeroForOne, false);
            assertEq(preview.limitTick, 200_100);
        }
    }

    function test_preview_sqrt_price_limit_reverts_when_slippage_is_too_high() external {
        vm.expectRevert("slippage>bsp");
        helper.previewSqrtPriceLimitX96(address(usdc), address(weth), fee, 10_001);
    }

    function test_preview_sqrt_price_limit_reverts_when_pool_missing() external {
        vm.expectRevert("pool not found");
        helper.previewSqrtPriceLimitX96(address(usdc), address(weth), 3000, 100);
    }
}
