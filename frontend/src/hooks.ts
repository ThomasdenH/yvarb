import { useReducer } from "react";

export const useAddableList = <T>(isEqual: (a: T, b: T) => boolean = (a: T, b: T) => a === b) => useReducer(
    (list: T[], n: T) => {
        if (!list.some(existing => isEqual(existing, n)))
            return [...list, n];
        return list;
    },
    []
);
