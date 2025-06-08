// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Auction {
    address public owner;
    uint public auctionEndTime;
    bool public ended = false;

    uint public highestBid;
    address public highestBidder;

    // Registro de todas las ofertas por dirección
    mapping(address => uint[]) public bidsByAddress;

    // Registro del total de fondos depositados por dirección
    mapping(address => uint) public deposits;

    // Lista de todos los oferentes únicos
    address[] public biddersList;

    // Protección básica contra reentrancia
    bool private locked = false;

    event NewBid(address indexed bidder, uint amount);
    event PartialRefund(address indexed user, uint amount);
    event AuctionEnded(address indexed winner, uint winningAmount);

    modifier onlyWhileActive() {
        require(block.timestamp < auctionEndTime, "La subasta ha terminado.");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Acceso denegado: solo el propietario puede hacer esto.");
        _;
    }

    modifier noReentrancy() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
        auctionEndTime = block.timestamp + 10 minutes; // Puedes ajustarlo a 7 días: 10080 minutes
    }

    function placeBid() external payable onlyWhileActive {
        require(msg.value > 0, "El monto debe ser mayor a cero.");

        if (highestBid != 0) {
            uint minRequired = (highestBid * 105) / 100; // 5% más alta
            require(msg.value >= minRequired, "La oferta debe ser al menos un 5% mayor que la anterior.");
        }

        // Registrar oferente único
        if (bidsByAddress[msg.sender].length == 0) {
            biddersList.push(msg.sender);
        }

        // Registrar depósito y oferta
        deposits[msg.sender] += msg.value;
        bidsByAddress[msg.sender].push(msg.value);

        if (msg.value > highestBid) {
            highestBid = msg.value;
            highestBidder = msg.sender;
        }

        // Extensión dinámica
        if (block.timestamp >= auctionEndTime - 10 minutes) {
            auctionEndTime += 10 minutes;
        }

        emit NewBid(msg.sender, msg.value);
    }

    function requestPartialRefund() external onlyWhileActive noReentrancy {
        uint[] storage userBids = bidsByAddress[msg.sender];
        require(userBids.length > 0, "No tienes ofertas registradas.");

        // Última oferta válida
        uint lastBid = userBids[userBids.length - 1];

        // Total depositado
        uint totalDeposited = deposits[msg.sender];
        uint refundableAmount = totalDeposited - lastBid;

        require(refundableAmount > 0, "No hay monto reembolsable disponible.");

        deposits[msg.sender] -= refundableAmount;
        payable(msg.sender).transfer(refundableAmount);

        emit PartialRefund(msg.sender, refundableAmount);
    }

    function endAuction() external onlyOwner {
        require(block.timestamp >= auctionEndTime, "La subasta aún no ha terminado.");
        require(!ended, "La subasta ya finalizó.");
        ended = true;

        emit AuctionEnded(highestBidder, highestBid);
    }

    // Devuelve el ganador y el monto ganador
    function getWinner() external view returns (address, uint) {
        return (highestBidder, highestBid);
    }

    // Devuelve la lista de oferentes y el total ofertado por cada uno
    function getAllBidders() external view returns (address[] memory, uint[] memory) {
        uint count = 0;
        for (uint i = 0; i < biddersList.length; i++) {
            if (bidsByAddress[biddersList[i]].length > 0) {
                count++;
            }
        }
        address[] memory addresses = new address[](count);
        uint[] memory totals = new uint[](count);
        uint idx = 0;
        for (uint i = 0; i < biddersList.length; i++) {
            if (bidsByAddress[biddersList[i]].length > 0) {
                addresses[idx] = biddersList[i];
                totals[idx] = deposits[biddersList[i]];
                idx++;
            }
        }
        return (addresses, totals);
    }

    // Devuelve depósitos a no ganadores con comisión del 2%
    function withdrawIfNotWinner() external noReentrancy {
        require(ended, "La subasta no ha finalizado.");
        require(msg.sender != highestBidder, "El ganador no puede retirar.");
        uint amount = deposits[msg.sender];
        require(amount > 0, "No hay fondos para retirar.");
        uint commission = (amount * 2) / 100;
        uint refund = amount - commission;
        deposits[msg.sender] = 0;
        payable(msg.sender).transfer(refund);
    }
}