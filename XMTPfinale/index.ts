import { Client } from "@xmtp/xmtp-js";
import { ethers } from "ethers";
import * as dotenv from "dotenv";
import ABI from "./abis/ChatGpt.json";

dotenv.config();

interface Message {
  role: string;
  content: string;
}

interface ResponseFormat {
  action: string;
  params: string;
  response: string;
  suggestions: string[];
}

class XMTPContractInteraction {
  private xmtpClient: Client;
  private contract: ethers.Contract;
  private signer: ethers.Signer;
  private chatHistory: Map<string, Message[]> = new Map();

  constructor(private contractAddress: string) {}

  async initialize() {
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    this.signer = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

    this.xmtpClient = await Client.create(this.signer, { env: "production" });

    this.contract = new ethers.Contract(this.contractAddress, ABI, this.signer);

    console.log("Initialization complete");
    console.log(`XMTP address: ${await this.getXmtpAddress()}`);
  }

  async getXmtpAddress(): Promise<string> {
    return this.xmtpClient.address;
  }

  async listenForMessages() {
    console.log("Listening for new conversations...");
    
    for await (const conversation of await this.xmtpClient.conversations.stream()) {
      this.handleConversation(conversation);
    }
  }

  private async handleConversation(conversation: any) {
    console.log(`New conversation with ${conversation.peerAddress}`);

    for await (const message of await conversation.streamMessages()) {
      if (message.senderAddress === this.xmtpClient.address) continue;

      console.log(`Received message from ${message.senderAddress}: ${message.content}`);

      try {
        const { action, params } = this.parseMessage(message.content);
        await this.handleAction(action, params, conversation);
      } catch (error) {
        console.error("Error handling message:", error);
        await conversation.send("Error processing your request. Please try again.");
      }
    }
  }

  private parseMessage(content: string): { action: string; params: any } {
    const [action, ...paramParts] = content.split(' ');
    const params = paramParts.join(' ');
    return { action, params };
  }

  private async handleAction(action: string, params: any, conversation: any) {
    switch (action.toLowerCase()) {
      case 'startchat':
        await this.startChat(params, conversation);
        break;
      case 'addmessage':
        await this.addMessage(params, conversation);
        break;
      default:
        await conversation.send("Unknown action. Available actions: startchat, addmessage");
    }
  }

  private async startChat(message: string, conversation: any) {
    try {
      console.log("Starting new chat with message:", message);
      const tx = await this.contract.startChat(message);
      console.log("Transaction sent:", tx.hash);
      const receipt = await tx.wait();
      console.log("Transaction mined:", receipt.transactionHash);
      const event = receipt.events?.find((e: any) => e.event === 'ChatCreated');
      const chatId = event?.args?.chatId.toString();

      if (chatId === undefined) {
        console.error("Failed to get chat ID from event");
        await conversation.send("Failed to get chat ID");
        return;
      }

      console.log("Chat created with ID:", chatId);
      this.chatHistory.set(chatId, [{ role: 'user', content: message }]);

      const response = await this.waitForLLMResponse(chatId);
      console.log("LLM Response received:", response);
      await conversation.send(`Chat started successfully. Chat ID: ${chatId}\n\nAssistant: ${response.response}`);

      if (response.suggestions.length > 0) {
        await conversation.send(`Suggestions: ${response.suggestions.join(', ')}`);
      }
    } catch (error) {
      console.error("Error starting chat:", error);
      await conversation.send("Error starting chat. Please try again.");
    }
  }

  private async addMessage(params: string, conversation: any) {
    const [chatId, ...messageParts] = params.split(' ');
    const message = messageParts.join(' ');

    try {
      console.log(`Adding message to chat ${chatId}:`, message);
      const chatHistory = this.chatHistory.get(chatId) || [];
      chatHistory.push({ role: 'user', content: message });
      this.chatHistory.set(chatId, chatHistory);

      const tx = await this.contract.addMessage(message, chatId);
      console.log("Transaction sent:", tx.hash);
      const receipt = await tx.wait();
      console.log("Transaction mined:", receipt.transactionHash);

      const response = await this.waitForLLMResponse(chatId);
      console.log("LLM Response received:", response);
      await conversation.send(`Assistant: ${response.response}`);

      if (response.suggestions.length > 0) {
        await conversation.send(`Suggestions: ${response.suggestions.join(', ')}`);
      }
    } catch (error) {
      console.error("Error adding message:", error);
      await conversation.send("Error adding message. Please check the chat ID and try again.");
    }
  }

  private async waitForLLMResponse(chatId: string): Promise<ResponseFormat> {
    console.log(`Waiting for LLM response for chat ${chatId}`);
    const chatHistory = this.chatHistory.get(chatId) || [];
    let lastProcessedMessageIndex = chatHistory.length - 1;
    let assistantResponse: ResponseFormat | null = null;
    let attempts = 0;
    const maxAttempts = 30; // 1 minute timeout (2 seconds * 30)

    while (!assistantResponse && attempts < maxAttempts) {
      const newMessages = await this.getNewMessages(chatId, lastProcessedMessageIndex + 1);
      console.log(`Received ${newMessages.length} new messages`);
      if (newMessages.length > 0) {
        for (let msg of newMessages) {
          if (msg.role === "assistant") {
            assistantResponse = this.parseAssistantResponse(msg.content);
            lastProcessedMessageIndex++;
            chatHistory.push(msg);
            this.chatHistory.set(chatId, chatHistory);
            break;
          }
        }
      }
      if (!assistantResponse) {
        console.log(`No assistant response yet. Attempt ${attempts + 1}/${maxAttempts}`);
        await new Promise(resolve => setTimeout(resolve, 2000));
        attempts++;
      }
    }

    if (!assistantResponse) {
      console.error("Timeout waiting for LLM response");
      throw new Error("Timeout waiting for LLM response");
    }

    return assistantResponse;
  }

  private async getNewMessages(chatId: string, startIndex: number): Promise<Message[]> {
    try {
      const messages = await this.contract.getMessageHistory(chatId);
      return messages.slice(startIndex).map((message: any) => ({
        role: message.role,
        content: message.content[0].value,
      }));
    } catch (error) {
      console.error("Error fetching message history:", error);
      return [];
    }
  }

  private parseAssistantResponse(content: string): ResponseFormat {
    try {
      const parsedContent = JSON.parse(content);
      return {
        action: parsedContent.action || "",
        params: parsedContent.params || "",
        response: parsedContent.response || "",
        suggestions: Array.isArray(parsedContent.suggestions)
          ? parsedContent.suggestions
          : parsedContent.suggestions ? parsedContent.suggestions.split(',').map((s: string) => s.trim()) : []
      };
    } catch (error) {
      console.error("Error parsing assistant response:", error);
      return {
        action: "",
        params: "",
        response: content,
        suggestions: []
      };
    }
  }
}

async function main() {
  const contractAddress = process.env.CHAT_CONTRACT_ADDRESS;
  if (!contractAddress) {
    console.error("Missing CHAT_CONTRACT_ADDRESS in .env");
    return;
  }

  const app = new XMTPContractInteraction(contractAddress);

  try {
    await app.initialize();
    
    const xmtpAddress = await app.getXmtpAddress();
    if (!(await Client.canMessage(xmtpAddress))) {
      console.log("Initializing XMTP for this address...");
      await app.listenForMessages();
      console.log("XMTP initialized successfully");
    } else {
      await app.listenForMessages();
    }
  } catch (error) {
    console.error("An error occurred during initialization:", error);
  }
}

main().catch(console.error);