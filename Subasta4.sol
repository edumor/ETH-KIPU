// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//   Autor: Eduardo J. Moreno
//   Subasta descentralizada con reembolsos y comisión
//   Incluye extensión de tiempo y comisión del 2% a los retiros de no ganadores.

contract Subasta {
    // Variables de estado
    address public owner;
    address public highestBidder;
    uint public highestBid;
    uint public auctionEndTime;
    uint public initialEndTime;
    uint public maxEndTime;
    uint constant MIN_BID_INCREMENT_PERCENT = 5;
    uint constant EXTENSION_TIME = 10 minutes;
    uint constant COMMISSION_PERCENT = 2;
    uint constant DURATION_MINUTES = 10080; // 7 días
    uint constant MAX_EXTENSION_MINUTES = 10; // 10 minutos

    bool public auctionEnded;

    mapping(address => uint) public pendingReturns; // Depósitos reembolsables
    mapping(address => uint[]) private bidHistory;  // Historial de ofertas por usuario
    address[] private bidders; // Lista de oferentes únicos

    // Eventos
    event NewBid(address indexed bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    // Constructor: inicializa la subasta
    constructor() {
        owner = msg.sender;
        auctionEndTime = block.timestamp + (DURATION_MINUTES * 1 minutes);
        initialEndTime = auctionEndTime;
        maxEndTime = auctionEndTime + (MAX_EXTENSION_MINUTES * 1 minutes);
    }

    // Permite ofertar. La oferta debe ser al menos 5% mayor que la actual.
    function bid() external payable {
        require(block.timestamp < auctionEndTime, "Auction ended");
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
            pendingReturns[highestBidder] += highestBid;
        }

        highestBid = msg.value;
        highestBidder = msg.sender;

        // Extiende la subasta si la oferta se realiza en los últimos 10 minutos, pero no más allá de maxEndTime
        if (auctionEndTime - block.timestamp <= EXTENSION_TIME) {
            uint newEndTime = auctionEndTime + EXTENSION_TIME;
            auctionEndTime = newEndTime > maxEndTime ? maxEndTime : newEndTime;
        }

        emit NewBid(msg.sender, msg.value);
    }

    // Finaliza la subasta y transfiere el monto al owner (sin comisión)
    function endAuction() external {
        require(msg.sender == owner, "Only owner");
        require(block.timestamp >= auctionEndTime, "Auction not ended yet");
        require(!auctionEnded, "Auction already finalized");

        auctionEnded = true;

        // El owner recibe el 100% de la oferta ganadora
        (bool sentOwner, ) = payable(owner).call{value: highestBid}("");
        require(sentOwner, "Transfer to owner failed");

        emit AuctionEnded(highestBidder, highestBid);
    }

    // Permite a los postores no ganadores retirar sus fondos reembolsables (descontando 2% de comisión)
    function withdraw() external {
        require(auctionEnded, "Auction not ended yet");
        require(msg.sender != highestBidder, "Winner cannot withdraw");
        uint amount = pendingReturns[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingReturns[msg.sender] = 0;

        uint commission = (amount * COMMISSION_PERCENT) / 100;
        uint payout = amount - commission;

        // Envía la comisión al owner
        (bool sentCommission, ) = payable(owner).call{value: commission}("");
        require(sentCommission, "Commission transfer failed");

        // Envía el monto descontado al ofertante
        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        require(sent, "Ether send failed");
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
        pendingReturns[msg.sender] += totalRefund;
    }

    // Devuelve el postor ganador actual y el monto de su oferta
    function getWinner() external view returns (address, uint) {
        return (highestBidder, highestBid);
    }

    // Devuelve la lista de todos los oferentes y sus montos ofrecidos
    function getAllBiddersAndAmounts() external view returns (address[] memory, uint[] memory) {
        uint[] memory amounts = new uint[](bidders.length);
        for (uint i = 0; i < bidders.length; i++) {
            amounts[i] = pendingReturns[bidders[i]];
        }
        return (bidders, amounts);
    }

    // Devuelve todas las ofertas realizadas por un postor
    function getAllBids(address bidder) external view returns (uint[] memory) {
        return bidHistory[bidder];
    }
}