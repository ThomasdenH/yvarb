import { render, screen } from "@testing-library/react";
import '@testing-library/jest-dom';
import { ConnectWallet } from "./ConnectWallet";

describe('ConnectWallet', () => {
    it('should correctly connect', async () => {
        const connected = new Promise((resolve) => {
            const connectWallet = () => {
                resolve(undefined);
            }
            render(<ConnectWallet
                connectWallet={connectWallet}
                // eslint-disable-next-line @typescript-eslint/no-empty-function
                dismiss={() => {}}
            />);
        });
        const button = screen.getByText('Connect Wallet');
        expect(button).toBeInTheDocument();
        expect(screen.getByText("Please connect to your wallet.")).toBeInTheDocument();
        
        // Expect to be connected when clicking the button
        button.click();
        await connected;
    });

    it('should handle and dismiss network errors', () => {
        let dismissed = false;
        const networkErrorMessage = 'Network error!';
        render(<ConnectWallet
            // eslint-disable-next-line @typescript-eslint/no-empty-function
            connectWallet={() => {}}
            // eslint-disable-next-line @typescript-eslint/no-empty-function
            dismiss={() => { dismissed = true; }}
            networkError={networkErrorMessage}
        />);
        expect(screen.getByText(networkErrorMessage)).toBeInTheDocument();
        expect(dismissed).toBe(false);
        const dismissButton = screen.getByLabelText('Close');
        expect(dismissButton).toBeInTheDocument();
        dismissButton.click();
        expect(dismissed).toBe(true);
    });
});
