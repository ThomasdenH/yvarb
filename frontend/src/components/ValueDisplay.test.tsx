import { ValueDisplay, ValueType } from "./ValueDisplay";
import { render, screen } from "@testing-library/react";
import '@testing-library/jest-dom';
import { utils } from "ethers";

describe('ValueDisplay', () => {
    it('should display values correctly', () => {
        render(<ValueDisplay 
            value={utils.parseUnits('126.34', 'ether')}
            valueType={ValueType.Weth}
            label={'Label:'}
        />);
        expect(screen.getByText('Label:')).toBeInTheDocument()
        expect(screen.getByText('126.340000 WETH')).toBeInTheDocument();
    });
});
