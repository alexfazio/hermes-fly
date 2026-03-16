import QRCode from "qrcode";

export interface QrCodeRendererPort {
  render(data: string): Promise<string>;
}

export class TerminalQrCodeRenderer implements QrCodeRendererPort {
  async render(data: string): Promise<string> {
    return await QRCode.toString(data, {
      type: "terminal",
      small: true,
      margin: 1,
    });
  }
}
