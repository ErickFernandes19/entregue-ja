package com.entregueja.backend.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "usuarios")
public class Usuario {

    @ManyToOne
    @JoinColumn(name = "empresa_id")
    private Empresa empresa;

    @ManyToOne
    @JoinColumn(name = "empresa_pendente_id")
    private Empresa empresaPendente;

    private LocalDateTime dataVinculo;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String nome;

    @Column(unique = true)
    private String email;

    @Column(length = 255)
    private String senha;

    private String veiculo;

    private String capacidadeCarga;

    private String foto;

    @Column(length = 10)
    private String codigoRecuperacao;

    private LocalDateTime codigoRecuperacaoExpira;

    public Usuario() {
    }

    public Usuario(
            Long id,
            String nome,
            String email,
            String senha
    ) {
        this.id = id;
        this.nome = nome;
        this.email = email;
        this.senha = senha;
    }

    public Empresa getEmpresa() {
        return empresa;
    }

    public void setEmpresa(Empresa empresa) {
        this.empresa = empresa;
    }

    public Empresa getEmpresaPendente() {
        return empresaPendente;
    }

    public void setEmpresaPendente(Empresa empresaPendente) {
        this.empresaPendente = empresaPendente;
    }

    public LocalDateTime getDataVinculo() {
        return dataVinculo;
    }

    public void setDataVinculo(LocalDateTime dataVinculo) {
        this.dataVinculo = dataVinculo;
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

    public String getVeiculo() {
        return veiculo;
    }

    public void setVeiculo(String veiculo) {
        this.veiculo = veiculo;
    }

    public String getCapacidadeCarga() {
        return capacidadeCarga;
    }

    public void setCapacidadeCarga(String capacidadeCarga) {
        this.capacidadeCarga = capacidadeCarga;
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