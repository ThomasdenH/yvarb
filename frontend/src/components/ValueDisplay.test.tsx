import { ValueDisplay, ValueType } from "./ValueDisplay";
import { render, screen } from "@testing-library/react";
import '@testing-library/jest-dom';
import { utils } from "ethers";
import { AssetId } from "../App";

describe('ValueDisplay', () => {
    it('should display values correctly', () => {
        render(<ValueDisplay 
            value={utils.parseUnits('126.34', 'ether')}
            valueType={ValueType.Balance}
            token={AssetId.WEth}
            label={'Label:'}
        />);
        expect(screen.getByText('Label:')).toBeInTheDocument()
        expect(screen.getByText('126.340000 WETH')).toBeInTheDocument();
    });
});
