// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVoucher {

    event ApproveVoucher(address sender, address recipient, uint256 amount);

    event SettleVoucherAmount(address sender, address payer, uint256 amount);

    event RelinquishVoucherAmount(address sender, address payer, uint256 amount);

    function approveVoucher(address recipient, uint256 amount) external;

    function settleVoucherAmount(address payer, uint256 amount) external;

    function relinquishVoucherAmount(address payer, uint256 amount) external;

    function voucherBalanceOf(address payer) external view returns (uint256);

    function settlerBalanceOf(address payer, address settler) external view returns(uint256);
}