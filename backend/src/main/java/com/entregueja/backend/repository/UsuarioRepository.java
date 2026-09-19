package com.entregueja.backend.repository;

import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {

    Optional<Usuario> findByEmail(String email);

    List<Usuario> findByEmpresa(Empresa empresa);

    long countByEmpresa(Empresa empresa);

    List<Usuario> findByEmpresaPendente(Empresa empresa);
}