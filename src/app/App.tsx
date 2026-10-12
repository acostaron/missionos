import { RouterProvider } from 'react-router-dom';
import { AppProviders } from './providers';
import { router } from './router';
import { PwaBanners } from '../components/pwa/PwaBanners';

export function App() {
  return (
    <AppProviders>
      <PwaBanners />
      <RouterProvider router={router} />
    </AppProviders>
  );
}

export default App;
