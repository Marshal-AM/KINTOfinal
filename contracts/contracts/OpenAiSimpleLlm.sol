// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

// @title OpenAiChatGpt
// @notice This contract interacts with teeML oracle to handle chat interactions using the OpenAI model.
contract ImprovedOpenAiSimpleLLM {

    struct ChatRun {
        address owner;
        IOracle.Message[] messages;
        uint messagesCount;
    }

    // @notice Mapping from chat ID to ChatRun
    mapping(uint => ChatRun) public chatRuns;
    uint private chatRunsCount;

    // @notice Event emitted when a new chat is created
    event ChatCreated(address indexed owner, uint indexed chatId);

    // @notice Address of the contract owner
    address private owner;

    // @notice Address of the oracle contract
    address public oracleAddress;

    // @notice Event emitted when the oracle address is updated
    event OracleAddressUpdated(address indexed newOracleAddress);

    // @notice Configuration for the OpenAI request
    IOracle.OpenAiRequest private config;

    // @notice System prompt to be used for each chat
    string private constant SYSTEM_PROMPT = "1.) You are an expert in DeFi who answers users questions by maintaining proper context by remembering whatever the user talked in the previous conversation. BE EXTREMEY CONCISE and Natural without using too much formal/technical words, make people understand easily what you mean.\n"
                                          "2.) NECESSARY: YOU HAVE TO Provide financial advice AND make predictions of crypto prices too.\n"
                                          "NOTE: YOU COULD SEARCH THE INTERNET AND TELL MARKET TRENDS TO THE USERS!!!\n"
                                          "ESSENTIAL: If the user wants you to talk in a different language, talk in the language they want you to talk. NEVER HESITATE!!!\n"

                                          "3.) VERY VERY EXREMELY IMPORTANT: You will be providing 4 outputs to me in this format and NOTHING MORE OR LESS!!!\n"
                                          "{\n"
                                          "    \"action\": \"\",\n"
                                          "    \"params\": \"\",\n"
                                          "    \"response\": \"\"\n"
                                          "    \"suggestions\": \"\"\n"
                                          "}\n"

                                          "NO MISTAKE IN THE FORMAT SHOULD BE DONE IN ANY WAY AT ALL!!!"
                                          "4.) The response should hold the response you generate. DO NOT YAP. Be concise in your response and give points or proper spacing between paragraphs for the user to read the response section easily.\n"
                                          "5.) The params and action should be empty until the user asks you to swap or check balance or for position\n"
                                          "6.) If the user asks to swap, then enter the action as swap\n"
		                                  "7.) If the user asks to position, then enter the action as position\n"
                                      
                                  
                                      
                                   
                                          "8.) If the user wants to swap, ask questions like what coin they want to swap, the coin which is gonna be replaced, the amount of coins, and the slippage. NOTE: Users can choose slippage between 0.1 and 5, by default it has to be 0.1\n."
                                          "9.) If the user wants to position, ask questions like what tokens they want to postion, not more or less than 2 tokens has to be provided."
                                         
                                          "10.) For swap, once you've asked all questions the param value should be like this <7887>_<token_in>_<token_out>_<slippage>_<amount>\n"
                                          "11.) For position, once you've asked all questions the param value should be like this <7887>_<token_in>_<token_out>\n"
                                          "CAREFULLY FILL THE SUGGESTION SECTION as mentioned!!!:"
                                          "12.) If you ask a question like what coin the user wants to swap, provide the options as usdc, usdt, link, weth UNDER THE suggestions section ONLY!!!\n"
                                          "13.) If you ask a question like what coin the user wants to swap to, provide the other 3 options exempting the chosen one UNDER THE suggestions section\n"
                                          "14.) If you ask a question like what slippage the user wants to set provide the options as 0.1, 0.2, 0.3, 0.4 and 0.5 UNDER THE suggestions section ONLY!!!\n"
                                          "15.) If you ask a question like what token the user wants to position provide the options as usdc, usdt, link, weth under the suggestion section\n"
                                          "16.) Similarly for the token they want to position for ask what token they want to position for and provide the other 3 options exempting the chosen one UNDER THE suggestions section\n"
                                          "17.) VERY VERY IMPORTANT: Apart from providing suggestions for the actions, ALSO provide suggestions related to YOUR CORE FUNCTIONS. You could fill in the suggestions with questions, or actions like swap, balance, position, or fill it with ANY OF your core functions. BUT NEVER EVER leave it empty. All your suggestions SHOULD NEVER EVER be in ONE WORD, make it NATURAL. Eg: Make a swap. The suggestions should be comma seperated and provide around 4 to 6 suggestions for stuff NOT related to swap or position!!!"
                                          "17.) The chain, token_in, token_out should all be in their abbreviations and NEVER mention the whole name\n"
                                          "18.) REMINDER: Now if the user has a low number of tokens in any particular network mentioned for any action such as swap, tell the exact balance of that token present in that network and ask whether you could use the maximum amount of tokens present for any transaction to be performed.\n" 
                                         
                                          
                                          "19.) If you see a word named \"positions_page\" in your input, just say This is your Positions page powered by Uniswap!, where you can monitor and manage your Uniswap V3 positions. It displays your current positions, the net amount spent, and any claimed fees. You can view detailed information about each position, track recent transactions, and easily create new positions or add liquidity. The page also provides links to explore transaction details on the blockchain.\n"
                                          "20.) In the beginning you will receive an input like this. FOR EXAMPLE:\n"
                                          "const home = {\n"
                                          "    usdc: 231413413,\n"
                                          "    usdt: 3423423,\n"
                                          "    link: 3235246546536,\n"
                                          "    weth: 234234234,\n"
                                          "};\n"
                                          "I have mapped the chain Id with their respective balances, There is ONLY 1 Chain: where 7887 is Kinto. Once you get this input JUST SAY ""Hey Degen, I have analyzed your portfolio. Hit me up with any questions and I can guide you!\n"
                                          "Before performing any action, ask the user for confirmation!!!"
                                          "21.) The numbers next to the token name represents the current balance. For instance, native: 231413413 represents the usdc balance\n"
                                          "22.) THERE ARE 4 possible tokens to swap in Kinto are usdc, usdt, link, weth. If anyone tries to swap a different token, say YOU DONT SWAP THAT TOKEN!!!\n"
                                          "23.) NOTE: You are also needed to provide personalized investment recommendations\n"
                                          "24.) If someone asks about their amount of tokens they hold or their balance, simply answer their query and don't say that you're searching at that time. USERS don't wanna wait"
                                          "25.) You have to adapt to user defined risk level Strategies tailored to individual needs. For instance you have to ask a risk temperature from 0 to 1 and based on it you gotta give me strategies if I ask for financial investment advice";

    // @param initialOracleAddress Initial address of the oracle contract
    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        chatRunsCount = 0;

        config = IOracle.OpenAiRequest({
            model : "gpt-4-turbo-preview",
            frequencyPenalty : 21, // > 20 for null
            logitBias : "", // empty str for null
            maxTokens : 1000, // 0 for null
            presencePenalty : 21, // > 20 for null
            responseFormat : "{\"type\":\"text\"}",
            seed : 0, // null
            stop : "", // null
            temperature : 10, // Example temperature (scaled up, 10 means 1.0), > 20 means null
            topP : 101, // Percentage 0-100, > 100 means null
            tools : "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"code_interpreter\",\"description\":\"Evaluates python code in a sandbox environment. The environment resets on every execution. You must send the whole script every time and print your outputs. Script should be pure python code that can be evaluated. It should be in python format NOT markdown. The code should NOT be wrapped in backticks. All python packages including requests, matplotlib, scipy, numpy, pandas, etc are available. Output can only be read from stdout, and stdin. Do not use things like plot.show() as it will not work. print() any output and results so you can capture the output.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"The pure python script to be evaluated. The contents will be in main.py. It should not be in markdown format.\"}},\"required\":[\"code\"]}}}]",
            toolChoice : "auto", // "none" or "auto"
            user : "" // null
        });
    }

    // @notice Ensures the caller is the contract owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    // @notice Ensures the caller is the oracle contract
    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    // @notice Updates the oracle address
    // @param newOracleAddress The new oracle address to set
    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

    // @notice Starts a new chat
    // @param message The initial message to start the chat with
    // @return The ID of the newly created chat
    function startChat(string memory message) public returns (uint) {
        ChatRun storage run = chatRuns[chatRunsCount];

        run.owner = msg.sender;
        
        // Add system message
        IOracle.Message memory systemMessage = createTextMessage("system", SYSTEM_PROMPT);
        run.messages.push(systemMessage);
        
        // Add user message
        IOracle.Message memory userMessage = createTextMessage("user", message);
        run.messages.push(userMessage);
        
        run.messagesCount = 2;

        uint currentId = chatRunsCount;
        chatRunsCount = chatRunsCount + 1;

        IOracle(oracleAddress).createOpenAiLlmCall(currentId, config);
        emit ChatCreated(msg.sender, currentId);

        return currentId;
    }

    // @notice Handles the response from the oracle for an OpenAI LLM call
    // @param runId The ID of the chat run
    // @param response The response from the oracle
    // @param errorMessage Any error message
    // @dev Called by teeML oracle
    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("user")),
            "No message to respond to"
        );

        if (!compareStrings(errorMessage, "")) {
            IOracle.Message memory newMessage = createTextMessage("assistant", errorMessage);
            run.messages.push(newMessage);
            run.messagesCount++;
        } else {
            if (compareStrings(response.content, "")) {
                IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            } else {
                IOracle.Message memory newMessage = createTextMessage("assistant", response.content);
                run.messages.push(newMessage);
                run.messagesCount++;
            }
        }
    }

    // @notice Handles the response from the oracle for a function call
    // @param runId The ID of the chat run
    // @param response The response from the oracle
    // @param errorMessage Any error message
    // @dev Called by teeML oracle
    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            compareStrings(run.messages[run.messagesCount - 1].role, "user"),
            "No function to respond to"
        );
        if (compareStrings(errorMessage, "")) {
            IOracle.Message memory newMessage = createTextMessage("user", response);
            run.messages.push(newMessage);
            run.messagesCount++;
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    // @notice Adds a new message to an existing chat run
    // @param message The new message to add
    // @param runId The ID of the chat run
    function addMessage(string memory message, uint runId) public {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("assistant")),
            "No response to previous message"
        );
        require(
            run.owner == msg.sender, "Only chat owner can add messages"
        );

        IOracle.Message memory newMessage = createTextMessage("user", message);
        run.messages.push(newMessage);
        run.messagesCount++;

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    // @notice Retrieves the message history of a chat run
    // @param chatId The ID of the chat run
    // @return An array of messages
    // @dev Called by teeML oracle
    function getMessageHistory(uint chatId) public view returns (IOracle.Message[] memory) {
        return chatRuns[chatId].messages;
    }

    // @notice Creates a text message with the given role and content
    // @param role The role of the message
    // @param content The content of the message
    // @return The created message
    function createTextMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage = IOracle.Message({
            role: role,
            content: new IOracle.Content[](1)
        });
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    // @notice Compares two strings for equality
    // @param a The first string
    // @param b The second string
    // @return True if the strings are equal, false otherwise
    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}