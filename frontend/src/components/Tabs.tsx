import React from "react";
import './Tabs.scss';

interface State {
  selectedTab: number;
}

interface TabComponent extends React.ReactElement {
  props: { label: string };
}

interface Props {
  children: TabComponent[];
}

export class Tabs extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      selectedTab: 0,
    };
  }

  render(): React.ReactNode {
    const tabNames = this.props.children.map((child) => child.props.label);
    return (
      <div>
        <div className='tabs'>
          {tabNames.map((value, index) => (
            <p
              key={value}
              className={
                index === this.state.selectedTab ? "tab selected" : "tab"
              }
              onClick={() => this.onClick(index)}
            >
              {value}
            </p>
          ))}
        </div>
        <div className='tabcontainer'>{this.props.children[this.state.selectedTab]}</div>
      </div>
    );
  }

  private onClick(selectedTab: number) {
    this.setState({ selectedTab });
  }
}
