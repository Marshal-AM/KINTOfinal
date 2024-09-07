import { Contract, ethers, Wallet, TransactionReceipt } from "ethers";
import ABI from "./abis/ChatGpt.json";
import express from 'express';
import dotenv from 'dotenv';

dotenv.config();

interface Message {
  role: string;
  content: string;
}

interface ResponseFormat {
  action: string;
  params: string;
  response: string;
  suggestions: string[];  // Changed to array
}

const app = express();
app.use(express.json());

let chatHistory: Message[] = []; // To store chat history

app.post('/start-chat', async (req, res) => {
  const rpcUrl = process.env.RPC_URL;
  if (!rpcUrl) return res.status(500).send("Missing RPC_URL in .env");
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) return res.status(500).send("Missing PRIVATE_KEY in .env");
  const contractAddress = process.env.CHAT_CONTRACT_ADDRESS;
  if (!contractAddress) return res.status(500).send("Missing CHAT_CONTRACT_ADDRESS in .env");

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new Wallet(privateKey, provider);
  const contract = new Contract(contractAddress, ABI, wallet);

  try {
    const message = req.body.message;
    if (!message) return res.status(400).send("Message is required");

    // Add the user's message to the chat history
    chatHistory.push({ role: 'user', content: message });

    // Send the entire chat history to the contract
    const fullConversation = chatHistory.map(msg => msg.content).join('\n');
    const transactionResponse = await contract.startChat(fullConversation);
    const receipt = await transactionResponse.wait();

    let chatId = getChatId(receipt, contract);
    if (chatId === undefined) {
      return res.status(500).send("Failed to get chat ID");
    }

    let lastProcessedMessageIndex = -1;
    let assistantResponse: ResponseFormat | null = null;

    while (!assistantResponse) {
      const newMessages: Message[] = await getNewMessages(contract, chatId, lastProcessedMessageIndex + 1);
      if (newMessages.length > 0) {
        for (let msg of newMessages) {
          if (msg.role === "assistant") {
            assistantResponse = parseAssistantResponse(msg.content);
            lastProcessedMessageIndex++;
            chatHistory.push(msg); // Add the assistant's response to the chat history
            break;
          }
        }
      }
      if (!assistantResponse) {
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }

    res.status(200).json(assistantResponse);
  } catch (error) {
    console.error("An error occurred:", error);
    res.status(500).send("An error occurred");
  }
});

function getChatId(receipt: TransactionReceipt, contract: Contract): number | undefined {
  for (const log of receipt.logs) {
    try {
      const parsedLog = contract.interface.parseLog(log);
      if (parsedLog && parsedLog.name === "ChatCreated") {
        return Number(parsedLog.args[1]);
      }
    } catch (error) {
      // Silently ignore parsing errors
    }
  }
}

async function getNewMessages(
  contract: Contract,
  chatId: number,
  startIndex: number
): Promise<Message[]> {
  const messages = await contract.getMessageHistory(chatId);
  return messages.slice(startIndex).map((message: any) => ({
    role: message.role,
    content: message.content[0].value,
  }));
}

// Updated to return suggestions as an array
function parseAssistantResponse(content: string): ResponseFormat {
  try {
    // Try to parse the content as JSON
    const parsedContent = JSON.parse(content);

    return {
      action: parsedContent.action || "",
      params: parsedContent.params || "",
      response: parsedContent.response || "",
      suggestions: Array.isArray(parsedContent.suggestions)
        ? parsedContent.suggestions
        : parsedContent.suggestions.split(',').map((s: string) => s.trim()) // If it's a string, split it into an array
    };
  } catch (error) {
    // Fallback in case parsing fails
    return {
      action: "",
      params: "",
      response: content,
      suggestions: [] // Default empty suggestions if not found
    };
  }
}

app.listen(3000, () => {
  console.log('Server is running on port 3000');
});
