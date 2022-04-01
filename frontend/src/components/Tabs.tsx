import React from "react";

interface State {
    tabs: string[],
    selected: number
}

export class Tabs extends React.Component<State, State> {
    constructor(props: State) {
        super(props);
        this.state = { ...props };
    }

    render(): React.ReactNode {
        return <div>
            {this.state.tabs.map((value, index) => {
                <p
                className={
                    index === this.state.selected ?
                        'tab selected' :
                        'tab'
                }>{value}</p>
            })}
        </div>
    }
}