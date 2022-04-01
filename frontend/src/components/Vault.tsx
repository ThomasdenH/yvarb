import React from "react";
import { Balance, Vault as VaultI } from "../objects/Vault";

interface State {
    vaultId: string,
    balance: Balance,
    vault: VaultI
}

interface Properties {
    vaultId: string,
    balance: Balance,
    vault: VaultI
}

export default class Vault extends React.Component<Properties, State> {
    constructor(props: Properties) {
        super(props);
        this.state = {
            ...props
        }
    }

    render(): React.ReactNode {
        return <p>{this.state.vaultId}</p>
    }
}
