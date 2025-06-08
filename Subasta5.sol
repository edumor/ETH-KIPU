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

    // Evento para nuevas ofertas
    event NewBid(address indexed bidder, uint amount);
    // Evento para reembolsos parciales
    event PartialRefund(address indexed user, uint amount);
    // Evento para el fin de la subasta
    event AuctionEnded(address indexed winner, uint winningAmount);

    // Modificador: solo permite ejecutar si la subasta está activa
    modifier onlyWhileActive() {
        require(block.timestamp < auctionEndTime, "La subasta ha terminado.");
        _;
    }

    // Modificador: solo permite ejecutar al owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Acceso denegado: solo el propietario puede hacer esto.");
        _;
    }

    // Modificador: protección básica contra reentrancia
    modifier noReentrancy() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    // Constructor: inicializa el owner y el tiempo de fin de subasta
    constructor() {
        owner = msg.sender;
        auctionEndTime = block.timestamp + 10 minutes; // Puedes ajustarlo a 7 días: 10080 minutes
    }

    // Permite recibir Ether directamente al contrato y emite un evento
    receive() external payable {
        emit NewBid(msg.sender, msg.value);
    }

    // Permite a un usuario ofertar en la subasta
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

        // Extensión dinámica: si faltan menos de 10 minutos, extiende la subasta
        if (block.timestamp >= auctionEndTime - 10 minutes) {
            auctionEndTime += 10 minutes;
        }

        emit NewBid(msg.sender, msg.value);
    }

    // Permite a un usuario retirar el excedente de sus depósitos (menos su última oferta)
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

    // Permite al owner finalizar la subasta
    function endAuction() external onlyOwner {
        require(block.timestamp >= auctionEndTime, "La subasta aun no ha terminado.");
        require(!ended, "La subasta ya finalizo.");
        ended = true;

        emit AuctionEnded(highestBidder, highestBid);
    }

    // Devuelve el ganador y el monto ganador
    function getWinner() external view returns (address, uint) {
        return (highestBidder, highestBid);
    }

    // Devuelve una porción de la lista de oferentes y sus depósitos (paginado)
    function getBiddersPaginated(uint start, uint count) external view returns (address[] memory, uint[] memory) {
        uint total = biddersList.length;
        if (start >= total) {
            return (new address[](0), new uint[](0));
        }
        uint end = start + count;
        if (end > total) {
            end = total;
        }
        uint resultCount = end - start;
        address[] memory addresses = new address[](resultCount);
        uint[] memory totals = new uint[](resultCount);
        for (uint i = 0; i < resultCount; i++) {
            address bidder = biddersList[start + i];
            addresses[i] = bidder;
            totals[i] = deposits[bidder];
        }
        return (addresses, totals);
    }

    // Permite a los no ganadores retirar su depósito menos una comisión del 2%
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

    // Permite al owner retirar fondos restantes del contrato tras finalizar la subasta
    function ownerWithdraw() external onlyOwner {
        require(ended, "La subasta no ha finalizado.");
        require(address(this).balance > 0, "No hay fondos.");
        payable(owner).transfer(address(this).balance);
    }
}