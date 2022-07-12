import { providers } from "ethers";
import { useEffect, useReducer, useState } from "react";

/**
 * Use an addable list as state. Updates by calling the provided function but
 * only if the element is not yet in the list.
 * @param isEqual Function to check for equality. Optional, if not provided
 * exact comparison will be used (`===`).
 */
export const useAddableList = <T>(
  isEqual: (a: T, b: T) => boolean = (a: T, b: T) => a === b
) =>
  useReducer((list: T[], n: T) => {
    if (!list.some((existing) => isEqual(existing, n))) return [...list, n];
    return list;
  }, []);

export type Invalidator = unknown & { readonly __tag: unique symbol };

/**
 * Creates a state variable that gets updated every time the invalidator is
 * called. This state variable can then be used to update hooks, for example a
 * `useEffect` hook.
 */
export const useInvalidator = (): [Invalidator, () => void] => {
  const [counter, setCounter] = useState(0);
  return [counter as unknown as Invalidator, () => setCounter((c) => c + 1)];
};

/**
 * Subscribe and unsubscribe to an Ethereum event.
 * @param event Event, must be global constant as this hook will not listen to
 *  updates.
 * @param fn The callback function, must be global constant as it does not
 *  listen to updates.
 */
export const useEthereumListener = (event: string, fn: providers.Listener) => {
  useEffect(() => {
    window.ethereum.on(event, fn);
    return () => {
      window.ethereum.removeListener(event, fn);
    };
    // Event must be constant
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
};
