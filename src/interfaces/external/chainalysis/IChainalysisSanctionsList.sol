// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IChainalysisSanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}
