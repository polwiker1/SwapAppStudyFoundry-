// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {SwappApp} from "../src/swappApp.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

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

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
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

contract SwapAppForkArbitrumTest is Test {
    address internal constant ARBITRUM_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address internal constant ARBITRUM_V2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    SwappApp app;
    GovernanceToken gov;

    address user = address(0xBEEF);
    address treasury = address(0xCAFE);

    function setUp() external {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));

        gov = new GovernanceToken("Governance", "GOV");
        app = new SwappApp(ARBITRUM_V2_ROUTER, ARBITRUM_V2_FACTORY, address(gov), treasury, 10, 3000, 1e18);
        gov.mint(address(app), 1_000_000e18);

        deal(USDC, user, 5_000e6);

        vm.prank(user);
        ERC20(USDC).approve(address(app), type(uint256).max);
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
        (, , uint256 liquidity) = app.addLiquiditySingleTokenUSDC(p);

        uint256 lpAfter = ERC20(lpToken).balanceOf(user);
        assertGt(liquidity, 0);
        assertEq(lpAfter, lpBefore + liquidity);
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
        (, , uint256 mintedLp) = app.addLiquiditySingleTokenUSDC(addP);

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
