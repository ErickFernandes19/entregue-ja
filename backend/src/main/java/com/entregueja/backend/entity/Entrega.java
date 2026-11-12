package com.entregueja.backend.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "entregas")
public class Entrega {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String cliente;
    private String endereco;
    private Double valor;
    private String complemento;
    private String observacao;
    private Boolean entregue = false;
    private String status = "PENDENTE";
    private Double latitude;
    private Double longitude;
    private String fotoComprovante;
    private String motivoNaoEntrega;

    @Column(length = 1000)
    private String justificativa;

    private LocalDateTime dataFinalizacao;
    private Double latitudeComprovante;
    private Double longitudeComprovante;

    private Double latitudeEntregador;
    private Double longitudeEntregador;
    private LocalDateTime dataAtualizacaoLocalizacao;

    @ManyToOne
    @JoinColumn(name = "empresa_id")
    private Empresa empresa;

    @ManyToOne
    @JoinColumn(name = "usuario_id")
    private Usuario entregador;

    public Entrega() {
    }

    public Entrega(Long id, String cliente, String endereco, Double valor,
                   String observacao, Boolean entregue, String status) {
        this.id = id;
        this.cliente = cliente;
        this.endereco = endereco;
        this.valor = valor;
        this.observacao = observacao;
        this.entregue = entregue;
        this.status = status;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getCliente() { return cliente; }
    public void setCliente(String cliente) { this.cliente = cliente; }

    public String getEndereco() { return endereco; }
    public void setEndereco(String endereco) { this.endereco = endereco; }

    public Double getValor() { return valor; }
    public void setValor(Double valor) { this.valor = valor; }

    public String getObservacao() { return observacao; }
    public void setObservacao(String observacao) { this.observacao = observacao; }

    public Boolean getEntregue() { return entregue; }
    public void setEntregue(Boolean entregue) { this.entregue = entregue; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getFotoComprovante() { return fotoComprovante; }
    public void setFotoComprovante(String fotoComprovante) { this.fotoComprovante = fotoComprovante; }

    public String getMotivoNaoEntrega() { return motivoNaoEntrega; }
    public void setMotivoNaoEntrega(String motivoNaoEntrega) { this.motivoNaoEntrega = motivoNaoEntrega; }

    public String getJustificativa() { return justificativa; }
    public void setJustificativa(String justificativa) { this.justificativa = justificativa; }

    public LocalDateTime getDataFinalizacao() { return dataFinalizacao; }
    public void setDataFinalizacao(LocalDateTime dataFinalizacao) { this.dataFinalizacao = dataFinalizacao; }

    public Double getLatitudeComprovante() { return latitudeComprovante; }
    public void setLatitudeComprovante(Double latitudeComprovante) { this.latitudeComprovante = latitudeComprovante; }

    public Double getLongitudeComprovante() { return longitudeComprovante; }
    public void setLongitudeComprovante(Double longitudeComprovante) { this.longitudeComprovante = longitudeComprovante; }

    public Empresa getEmpresa() { return empresa; }
    public void setEmpresa(Empresa empresa) { this.empresa = empresa; }

    public Usuario getEntregador() { return entregador; }
    public void setEntregador(Usuario entregador) { this.entregador = entregador; }

    public String getComplemento() { return complemento; }
    public void setComplemento(String complemento) { this.complemento = complemento; }

    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }

    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }

    public Double getLatitudeEntregador() { return latitudeEntregador; }
    public void setLatitudeEntregador(Double latitudeEntregador) { this.latitudeEntregador = latitudeEntregador; }

    public Double getLongitudeEntregador() { return longitudeEntregador; }
    public void setLongitudeEntregador(Double longitudeEntregador) { this.longitudeEntregador = longitudeEntregador; }

    public LocalDateTime getDataAtualizacaoLocalizacao() { return dataAtualizacaoLocalizacao; }
    public void setDataAtualizacaoLocalizacao(LocalDateTime dataAtualizacaoLocalizacao) {
        this.dataAtualizacaoLocalizacao = dataAtualizacaoLocalizacao;
    }
}
