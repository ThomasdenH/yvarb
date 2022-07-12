import { useEffect, useState } from "react";

const INTERVAL = 500;
export const Loading = () => {
    const [count, setCount] = useState(2);
    useEffect(() => {
        const pollId = setInterval(() => setCount((c) => (c + 1) % 3), INTERVAL);
        return () => clearInterval(pollId);
    })
    return <p>{`Loading.${'.'.repeat(count)}`}</p>;
};
