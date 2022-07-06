import { Tabs } from "./Tabs";
import { fireEvent, render, screen } from "@testing-library/react";
import '@testing-library/jest-dom';
import { BigNumber } from "ethers";
import { ValueInput } from "./ValueInput";

describe("Tabs", () => {
  it("should start at the first tab", () => {
    render(
      <Tabs tabs={[{ 
        label: 'Tab 1',
        component: <p>This is tab 1</p>
      }, {
        label: "Tab 2",
        component: <p>This is tab 2</p>
      }]} />
    );
    expect(screen.getByText('Tab 1')).toBeInTheDocument();
    expect(screen.getByText('Tab 2')).toBeInTheDocument();
    expect(screen.getByText('This is tab 1')).toBeInTheDocument();
    expect(screen.queryByText('This is tab 2')).toBeNull();
  });

  it("should have clickable tabs", () => {
    render(
      <Tabs tabs={[{ 
        label: 'Tab 1',
        component: <p>This is tab 1</p>
      }, {
        label: "Tab 2",
        component: <p>This is tab 2</p>
      }]} />
    );
    const tab2 = screen.getByText('Tab 2');
    tab2.click();
    expect(screen.getByText('Tab 1')).toBeInTheDocument();
    expect(tab2).toBeInTheDocument();
    expect(screen.queryByText('This is tab 1')).toBeNull();
    expect(screen.getByText('This is tab 2')).toBeInTheDocument();
  });
});
