import React, { useState } from "react";
import "./Tabs.scss";

export interface TabsType {
  label: string;
  component: JSX.Element;
}

interface Props {
  tabs: TabsType[];
}

export const Tabs: React.FunctionComponent<Props> = ({ tabs }) => {
  const [selectedTab, setSelectedTab] = useState(0);
  return (
    <div>
      <div className="tabs">
        {tabs.map(({ label }, index) => (
          <p
            key={label}
            className={index === selectedTab ? "tab selected" : "tab"}
            onClick={() => setSelectedTab(index)}
          >
            {label}
          </p>
        ))}
      </div>
      <div className="tabcontainer">{tabs[selectedTab].component}</div>
    </div>
  );
};
