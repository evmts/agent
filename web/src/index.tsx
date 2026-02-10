/* @refresh reload */
import { render } from 'solid-js/web';
import App from './App';
import './styles/tokens.css';
import './tailwind.css';

const root = document.getElementById('root');
if (!root) throw new Error('Missing #root element');
render(() => <App />, root);
