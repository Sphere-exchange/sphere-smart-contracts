// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract Chat  {

    infoChat[] public allChat;

     struct infoChat {
        address sender;
        string messageData;
        uint256 time;
    }

    function allChatsLength() external view returns (uint256) {
        return allChat.length;
    }

    function chat(string calldata message) public {
        allChat.push(infoChat(
            msg.sender,
            message,
            block.timestamp
        ));
    }

    function getLatestMessageChat(uint256 amountChat) public view returns (infoChat[] memory) {
        if(allChat.length <= amountChat){
            amountChat = allChat.length;
        }
        infoChat[] memory dataChat = new infoChat[](amountChat);
        uint256 latestChat = allChat.length - 1;
        for (uint256 i = 0; i < amountChat;  i++) 
        {
            dataChat[i] = allChat[latestChat];
            if(latestChat > 0){
                latestChat--;
            }
        }
        return dataChat;
    }
}
