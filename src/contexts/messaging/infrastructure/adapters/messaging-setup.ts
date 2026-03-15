export interface MessagingSetupPort {
  collectTelegramBotToken(): Promise<string>;
}

export class InteractiveMessagingSetup implements MessagingSetupPort {
  async collectTelegramBotToken(): Promise<string> {
    // In real implementation, prompts user interactively
    return "";
  }
}
