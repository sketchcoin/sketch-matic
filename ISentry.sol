// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISentry {


    event BlacklistedAddressAdded(address addr, uint256 timestamp);

    event BlacklistedAddressRemoved(address addr, uint256 timestamp);

    function addToBlacklist(address addr) external returns(bool sucess);

    function removeFromBlacklist(address addr) external returns(bool sucess);

    function blacklistedTime(address addr) external view returns (uint256 blacklistedTime);

}