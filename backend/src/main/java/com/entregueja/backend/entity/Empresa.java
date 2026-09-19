package com.entregueja.backend.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "empresas")
public class Empresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String nome;

    @Column(unique = true)
    private String email;

    @Column(length = 255)
    private String senha;

    private String foto;

    @Column(length = 10)
    private String codigoRecuperacao;

    private LocalDateTime codigoRecuperacaoExpira;

    public Empresa() {
    }

    public Empresa(
            String nome,
            String email,
            String senha
    ) {
        this.nome = nome;
        this.email = email;
        this.senha = senha;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getNome() {
        return nome;
    }

    public void setNome(String nome) {
        this.nome = nome;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getSenha() {
        return senha;
    }

    public void setSenha(String senha) {
        this.senha = senha;
    }

    public String getFoto() {
        return foto;
    }

    public void setFoto(String foto) {
        this.foto = foto;
    }

    public String getCodigoRecuperacao() {
        return codigoRecuperacao;
    }

    public void setCodigoRecuperacao(String codigoRecuperacao) {
        this.codigoRecuperacao = codigoRecuperacao;
    }

    public LocalDateTime getCodigoRecuperacaoExpira() {
        return codigoRecuperacaoExpira;
    }

    public void setCodigoRecuperacaoExpira(
            LocalDateTime codigoRecuperacaoExpira
    ) {
        this.codigoRecuperacaoExpira = codigoRecuperacaoExpira;
    }
}