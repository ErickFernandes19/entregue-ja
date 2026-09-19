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

    private String observacao;

    private Boolean entregue = false;

    private String status = "PENDENTE";

    /*
     * Caminho da foto usada como comprovante da entrega
     * ou da tentativa de entrega.
     *
     * Exemplo:
     * /uploads/entregas/15_1723650000_foto.jpg
     */
    private String fotoComprovante;

    /*
     * Motivo padronizado quando a entrega não for concluída.
     *
     * Exemplos:
     * DESTINATARIO_AUSENTE
     * ENDERECO_NAO_LOCALIZADO
     * DESTINATARIO_RECUSOU
     * LOCAL_FECHADO
     * OUTRO
     */
    private String motivoNaoEntrega;

    /*
     * Texto informado pelo entregador.
     */
    @Column(length = 1000)
    private String justificativa;

    /*
     * Data e hora em que a entrega ou tentativa
     * foi registrada.
     */
    private LocalDateTime dataFinalizacao;

    /*
     * Localização do entregador no momento
     * em que registrou o comprovante.
     */
    private Double latitudeComprovante;

    private Double longitudeComprovante;

    @ManyToOne
    @JoinColumn(name = "empresa_id")
    private Empresa empresa;

    @ManyToOne
    @JoinColumn(name = "usuario_id")
    private Usuario entregador;

    public Entrega() {
    }

    public Entrega(
            Long id,
            String cliente,
            String endereco,
            Double valor,
            String observacao,
            Boolean entregue,
            String status
    ) {
        this.id = id;
        this.cliente = cliente;
        this.endereco = endereco;
        this.valor = valor;
        this.observacao = observacao;
        this.entregue = entregue;
        this.status = status;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getCliente() {
        return cliente;
    }

    public void setCliente(String cliente) {
        this.cliente = cliente;
    }

    public String getEndereco() {
        return endereco;
    }

    public void setEndereco(String endereco) {
        this.endereco = endereco;
    }

    public Double getValor() {
        return valor;
    }

    public void setValor(Double valor) {
        this.valor = valor;
    }

    public String getObservacao() {
        return observacao;
    }

    public void setObservacao(String observacao) {
        this.observacao = observacao;
    }

    public Boolean getEntregue() {
        return entregue;
    }

    public void setEntregue(Boolean entregue) {
        this.entregue = entregue;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getFotoComprovante() {
        return fotoComprovante;
    }

    public void setFotoComprovante(String fotoComprovante) {
        this.fotoComprovante = fotoComprovante;
    }

    public String getMotivoNaoEntrega() {
        return motivoNaoEntrega;
    }

    public void setMotivoNaoEntrega(String motivoNaoEntrega) {
        this.motivoNaoEntrega = motivoNaoEntrega;
    }

    public String getJustificativa() {
        return justificativa;
    }

    public void setJustificativa(String justificativa) {
        this.justificativa = justificativa;
    }

    public LocalDateTime getDataFinalizacao() {
        return dataFinalizacao;
    }

    public void setDataFinalizacao(LocalDateTime dataFinalizacao) {
        this.dataFinalizacao = dataFinalizacao;
    }

    public Double getLatitudeComprovante() {
        return latitudeComprovante;
    }

    public void setLatitudeComprovante(Double latitudeComprovante) {
        this.latitudeComprovante = latitudeComprovante;
    }

    public Double getLongitudeComprovante() {
        return longitudeComprovante;
    }

    public void setLongitudeComprovante(Double longitudeComprovante) {
        this.longitudeComprovante = longitudeComprovante;
    }

    public Empresa getEmpresa() {
        return empresa;
    }

    public void setEmpresa(Empresa empresa) {
        this.empresa = empresa;
    }

    public Usuario getEntregador() {
        return entregador;
    }

    public void setEntregador(Usuario entregador) {
        this.entregador = entregador;
    }
}