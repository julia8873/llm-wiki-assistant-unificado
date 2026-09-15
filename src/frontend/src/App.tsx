import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import { AuthGuard, RoleGuard } from './components/AuthGuard';
import { Layout } from './components/Layout';
import { Login } from './components/Login';
import { CourseDashboard } from './components/CourseDashboard';
import { StudentProfile } from './components/StudentProfile';
import { TeacherHome } from './components/TeacherHome';
import { TeacherProfile } from './components/TeacherProfile';

import { useAuth } from './context/AuthContext';

const HomeRedirect: React.FC = () => {
  const { user, logout } = useAuth();
  if (!user || !user.allowed_courses || user.allowed_courses.length === 0) {
    // Usuario autenticado pero sin cursos asignados todavía
    return (
      <div className="container" style={{ display: 'flex', minHeight: '100vh', alignItems: 'center', justifyContent: 'center' }}>
        <div className="card" style={{ maxWidth: '480px', width: '100%', textAlign: 'center' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>📋</div>
          <h2>Sin cursos asignados</h2>
          <p className="mt-4" style={{ color: 'var(--text-muted)' }}>
            Tu usuario <strong>{user?.sub}</strong> está autenticado correctamente,
            pero aún no tienes ningún curso asignado en el sistema.
          </p>
          <p className="mt-2" style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>
            Contacta con el administrador para que te asigne a un curso.
          </p>
          <button
            className="btn-primary mt-6"
            onClick={logout}
            style={{ marginTop: '1.5rem' }}
          >
            Cerrar sesión
          </button>
        </div>
      </div>
    );
  }
  if (user.is_teacher) {
    return <TeacherHome />;
  }
  return <Navigate to={`/course/${user.allowed_courses[0]}/student/${user.moodle_user_id}`} replace />;
};

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          
          <Route element={<AuthGuard />}>
            <Route element={<Layout />}>
              <Route path="/" element={<HomeRedirect />} />
              
              <Route element={<RoleGuard requireTeacher={true} />}>
                <Route path="/course/:courseId" element={<CourseDashboard />} />
                <Route path="/profile" element={<TeacherProfile />} />
              </Route>
              
              <Route path="/course/:courseId/student/:studentId" element={<StudentProfile />} />
            </Route>
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
