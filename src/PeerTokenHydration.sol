// SPDX-License-Identifier: Apache 2
pragma solidity >=0.6.12 <0.9.0;

import {PeerTokenLite} from "src/PeerTokenLite.sol";

/// @notice HDX peer token for burn-and-mint NTT deployments.
/// @dev Identical to {PeerTokenLite} except for the decimal count, which is
/// fixed at 12 to match HDX on Hydration. NttManager reads this via a
/// staticcall to `decimals()` and registers it as the peer decimals on every
/// other chain, so it must not diverge from the canonical token.
contract PeerTokenHydration is PeerTokenLite {
    constructor(string memory _name, string memory _symbol, address _minter, address _owner)
        PeerTokenLite(_name, _symbol, _minter, _owner)
    {}

    function decimals() public pure override returns (uint8) {
        return 12;
    }
}
