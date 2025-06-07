// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Subasta descentralizada con reembolsos y comisión
// Autor: Eduardo J. Moreno
contract Auction {
    // Variables de Estado
    address public owner;
    address public highestBidder;
    uint public highestBid;
    uint public auctionEndTime;
    uint public initialEndTime;
    uint constant MIN_BID_INCREMENT_PERCENT = 5;
    uint constant EXTENSION_TIME = 10 minutes;
    uint constant COMMISSION_PERCENT = 2;

    bool public auctionEnded;

    mapping(address => uint) public bids; // Fondos disponibles para retirar por cada usuario
    mapping(address => uint[]) private bidHistory; // Historial de ofertas por usuario
    address[] private bidders; // Lista de todos los oferentes únicos

    // Eventos
    event NewBid(address indexed bidder, uint amount);
    event AuctionEnded(address winner, uint amount);
    event Withdraw(address indexed bidder, uint amount);
    event PartialRefund(address indexed bidder, uint amount);

    // Modificadores 
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier auctionActive() {
        require(block.timestamp < auctionEndTime, "Auction has ended");
        _;
    }

    modifier auctionHasEnded() {
        require(block.timestamp >= auctionEndTime, "Auction has not ended yet");
        require(!auctionEnded, "Auction already finalized");
        _;
    }

    // Inicializa la subasta con una duración en minutos
    // _durationMinutes: Duración de la subasta en minutos
    constructor(uint _durationMinutes) {
        require(_durationMinutes > 0, "Duration must be greater than 0");
        owner = msg.sender;
        auctionEndTime = block.timestamp + (_durationMinutes * 1 minutes);
        initialEndTime = auctionEndTime;
    }

    // Permite ofertar, la oferta debe ser al menos 5% mayor que la actual
    function bid() external payable auctionActive {
        require(msg.value > 0, "Bid must be greater than zero");
        uint minIncrement = highestBid + ((highestBid * MIN_BID_INCREMENT_PERCENT) / 100);
        require(msg.value >= minIncrement, "Bid not high enough");

        // Si es la primera oferta del usuario, lo agregamos a la lista de bidders
        if (bidHistory[msg.sender].length == 0) {
            bidders.push(msg.sender);
        }

        // Guarda la oferta en el historial del usuario
        bidHistory[msg.sender].push(msg.value);

        // Reembolsa al postor anterior
        if (highestBid > 0) {
            bids[highestBidder] += highestBid;
        }

        highestBid = msg.value;
        highestBidder = msg.sender;

        // Extiende la subasta si la oferta se realiza en los últimos 10 minutos
        if (auctionEndTime - block.timestamp <= EXTENSION_TIME) {
            auctionEndTime += EXTENSION_TIME;
        }

        emit NewBid(msg.sender, msg.value);
    }

    // Finaliza la subasta y transfiere el monto al owner descontando la comisión
    function endAuction() external onlyOwner auctionHasEnded {
        auctionEnded = true;

        uint commission = (highestBid * COMMISSION_PERCENT) / 100;
        uint payout = highestBid - commission;

        // Transferir comisión al owner
        (bool sentOwner, ) = payable(owner).call{value: payout}("");
        require(sentOwner, "Transfer to owner failed");

        emit AuctionEnded(highestBidder, highestBid);
    }

    // Permite a los postores no ganadores retirar sus fondos reembolsables
    function withdraw() external {
        require(msg.sender != highestBidder, "Winner cannot withdraw");
        uint amount = bids[msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[msg.sender] = 0;
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Ether send failed");

        emit Withdraw(msg.sender, amount);
    }

    // Permite a los participantes solicitar el reembolso de ofertas previas menores a la oferta más alta actual
    function partialRefund() external {
        uint[] storage history = bidHistory[msg.sender];
        uint totalRefund;

        for (uint i = 0; i < history.length; i++) {
            if (history[i] < highestBid && history[i] > 0) {
                totalRefund += history[i];
                history[i] = 0;
            }
        }

        require(totalRefund > 0, "No refundable amount");
        bids[msg.sender] += totalRefund;
        emit PartialRefund(msg.sender, totalRefund);
    }

    // Devuelve todas las ofertas realizadas por un postor
    // bidder: Dirección del postor
    function getAllBids(address bidder) external view returns (uint[] memory) {
        return bidHistory[bidder];
    }

    // Devuelve el postor ganador actual y el monto de su oferta
    function getWinner() external view returns (address, uint) {
        return (highestBidder, highestBid);
    }

    // Devuelve la lista de todos los oferentes y sus montos ofrecidos
    function getAllBiddersAndAmounts() external view returns (address[] memory, uint[] memory) {
        uint[] memory amounts = new uint[](bidders.length);
        for (uint i = 0; i < bidders.length; i++) {
            amounts[i] = bids[bidders[i]];
        }
        return (bidders, amounts);
    }
}