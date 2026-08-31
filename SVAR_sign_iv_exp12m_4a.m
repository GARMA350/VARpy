%% ========================================================================
%  SVAR con identificación mixta: Instrumentos Externos + Restricciones de Signo
%  Método: Cesa-Bianchi & Sokol (2021), implementado en el VAR Toolbox
%  (Cesa-Bianchi) mediante VARopt.ident = 'sign+iv'
%
%  ESTE SCRIPT CORRE DOS MODELOS EN UNA SOLA EJECUCIÓN:
%    Modelo 1 ("exp12m"): expectativas de inflación a 12 meses
%                          archivo: data_nueva_trimestral.xlsx
%                          ventanas: 2008-2018, 2012-2022, 2016-2026
%                          horizonte de comparación de IRFs: 12 MESES (4 trimestres)
%    Modelo 2 ("exp4a"):  expectativas de inflación a 4 años
%                          archivo: data_nueva_trimestral_4a.xlsx
%                          ventanas: 2014-2024, 2016-2026
%                          horizonte de comparación de IRFs: 4 AÑOS (16 trimestres)
%
%  Ambos modelos comparten exactamente la misma metodología:
%   - igae -> brecha del producto (log + filtro HP, lambda=1600, trimestral)
%   - tcr  -> brecha del TCR      (log + filtro HP, lambda=1600, trimestral)
%   - Choque de política monetaria identificado con el instrumento externo mps
%   - Choques restantes (4) identificados con restricciones de signo,
%     condicionales al choque ya fijado por el IV (VARopt.ident='sign+iv')
%
%  SALIDA PRINCIPAL: al final, para cada modelo y para CADA uno de los 5
%  choques, se genera una figura con 5 subpaneles (uno por variable de
%  respuesta) donde se superponen las IRFs de TODAS las ventanas temporales
%  de ese modelo, truncadas al horizonte de interés (12m o 4a según el modelo).
% ========================================================================

clear; clc; close all;
if ~exist('graphics', 'dir'); mkdir('graphics'); end

%% 0) Especificación de los dos modelos
% ------------------------------------------------------------------------
modelos(1).nombre      = 'exp12m';
modelos(1).label       = 'Expectativas de Inflaci\''on a 12 Meses';
modelos(1).archivo     = 'data_nueva_trimestral.xlsx';
modelos(1).ventana_ini = [datetime(2008,1,1), datetime(2012,1,1), datetime(2016,1,1)];
modelos(1).ventana_fin = [datetime(2018,12,31), datetime(2022,12,31), datetime(2026,12,31)];
modelos(1).ventana_lbl = {'2008-2018', '2012-2022', '2016-2026'};
modelos(1).nsteps_irf  = 4;        % horizonte de comparación: 12 meses = 4 trimestres
modelos(1).horiz_label = '12 Meses';
modelos(1).pctg        = 90;
modelos(1).ndraws      = 1000;
modelos(1).sr_hor      = 3;
modelos(1).nlags       = 1;        % <-- AJUSTA con base en el resultado de VARlag (ver consola)

modelos(2).nombre      = 'exp4a';
modelos(2).label       = 'Expectativas de Inflaci\''on a 4 A\~nos';
modelos(2).archivo     = 'data_nueva_trimestral_4a.xlsx';
modelos(2).ventana_ini = [datetime(2014,1,1), datetime(2016,1,1)];
modelos(2).ventana_fin = [datetime(2024,12,31), datetime(2026,12,31)];
modelos(2).ventana_lbl = {'2014-2024', '2016-2026'};
modelos(2).nsteps_irf  = 16;       % horizonte de comparación: 4 años = 16 trimestres
modelos(2).horiz_label = '4 A\~nos';
modelos(2).pctg        = 84;
modelos(2).ndraws      = 500;
modelos(2).sr_hor      = 3;
modelos(2).nlags       = 1;        % <-- AJUSTA con base en el resultado de VARlag (ver consola)

n_modelos = numel(modelos);

%% 1) Estimar cada modelo (todas sus ventanas)
% ------------------------------------------------------------------------
resultados = cell(n_modelos,1);
for m = 1:n_modelos
    fprintf('\n============================================================\n');
    fprintf(' MODELO %d/%d: %s  (%s)\n', m, n_modelos, modelos(m).label, modelos(m).archivo);
    fprintf('============================================================\n');
    resultados{m} = estimar_svar_modelo(modelos(m));
end

%% 2) Gráficas finales: IRF de cada choque, todas las ventanas superpuestas
% ------------------------------------------------------------------------
% Una figura por choque y por modelo (5 choques x 2 modelos = 10 figuras),
% cada una con 5 subpaneles (una por variable de respuesta), superponiendo
% las ventanas temporales de ese modelo, truncada al horizonte de interés.
for m = 1:n_modelos
    graficar_comparacion_choques(resultados{m}, modelos(m));
end

fprintf('\nListo. Figuras comparativas guardadas en la carpeta "graphics/".\n');


%% ========================================================================
%  FUNCIONES LOCALES
% ========================================================================

function res = estimar_svar_modelo(spec)
% Carga los datos de un modelo, construye las brechas (HP), estima el SVAR
% sign+iv en cada ventana temporal, y devuelve todo lo necesario para las
% gráficas comparativas finales.

    %% 1) Cargar datos
    % --------------------------------------------------------------------
    Ttab = readtable(spec.archivo, 'Sheet', 'Hoja1');

    dates_dt = datetime(Ttab.Fecha);
    igae     = Ttab.igae;
    sub      = Ttab.sub;               % inflación (subyacente)
    tasa     = Ttab.tasa;              % tasa de interés (equivalente a cetes28)
    exp      = Ttab.exp;               % expectativas (12m o 4a, según el modelo)
    tcr      = Ttab.tcr;               % tipo de cambio real (en logaritmos, L_TCR)
    mps      = Ttab.mps;               % instrumento externo (mps, sumado por trimestre)

    T = height(Ttab);

    %% 1.0) Gráfica exploratoria de las series originales
    % --------------------------------------------------------------------
    fig_raw = figure('Name', sprintf('Series originales (%s)', spec.nombre));
    vars_raw  = {igae, sub, tasa, exp, tcr, mps};
    names_raw = {'IGAE (nivel, promedio trim.)','Inflaci\''on (sub)','Tasa de inter\''es', ...
                 'Expectativas','TCR (log, L\_TCR)','mps (instrumento, suma trim.)'};
    n_raw = numel(vars_raw);

    for i = 1:n_raw
        subplot(ceil(n_raw/2), 2, i);
        plot(dates_dt, vars_raw{i}, 'LineWidth', 1.2);
        title(names_raw{i}, 'Interpreter', 'latex');
        xlabel('Fecha'); grid on;
    end
    sgtitle(sprintf('Series originales trimestrales -- %s', spec.label), 'Interpreter', 'latex');
    print(fig_raw, '-dpdf', sprintf('graphics/series_originales_%s.pdf', spec.nombre));

    %% 1.1) Brecha del producto y brecha del TCR (filtro HP, lambda=1600)
    % --------------------------------------------------------------------
    lambda_hp = 1600;                  % lambda estándar para frecuencia TRIMESTRAL

    log_igae  = igae;
    [igae_trend, igae_cycle] = hpfilter(log_igae, 'Smoothing', lambda_hp);
    actividad = 100*igae_cycle;
    act_label = 'Brecha del producto (IGAE, filtro HP, \lambda=1600)';

    log_tcr = tcr;
    [tcr_trend, tcr_cycle] = hpfilter(log_tcr, 'Smoothing', lambda_hp);
    brecha_tcr = 100*tcr_cycle;
    tcr_label  = 'Brecha del TCR (filtro HP, \lambda=1600)';

    fig_hp = figure('Name', sprintf('Descomposici\''on HP (%s)', spec.nombre));
    subplot(2,2,1);
    plot(dates_dt, log_igae, 'k', dates_dt, igae_trend, 'r--', 'LineWidth', 1.2);
    title('log(IGAE): serie y tendencia HP', 'Interpreter','latex'); grid on;
    legend('log(IGAE)','Tendencia','Location','best');

    subplot(2,2,2);
    plot(dates_dt, actividad, 'b', 'LineWidth', 1.2); yline(0,'k:');
    title(act_label, 'Interpreter','latex'); grid on;

    subplot(2,2,3);
    plot(dates_dt, log_tcr, 'k', dates_dt, tcr_trend, 'r--', 'LineWidth', 1.2);
    title('L\_TCR: serie y tendencia HP', 'Interpreter','latex'); grid on;
    legend('L\_TCR','Tendencia','Location','best');

    subplot(2,2,4);
    plot(dates_dt, brecha_tcr, 'b', 'LineWidth', 1.2); yline(0,'k:');
    title(tcr_label, 'Interpreter','latex'); grid on;

    sgtitle(sprintf('Descomposici\''on HP ($\\lambda=1600$) -- %s', spec.label), 'Interpreter','latex');
    print(fig_hp, '-dpdf', sprintf('graphics/descomposicion_hp_%s.pdf', spec.nombre));

    %% 1.2) Chequeo de estacionariedad (ADF + KPSS)
    % --------------------------------------------------------------------
    act_clean = actividad(~isnan(actividad));
    tcr_clean = brecha_tcr(~isnan(brecha_tcr));

    if exist('adftest','file') == 2 && exist('kpsstest','file') == 2
        [h_adf, p_adf]       = adftest(act_clean);
        [h_kpss, p_kpss]     = kpsstest(act_clean);
        [h_adf_t, p_adf_t]   = adftest(tcr_clean);
        [h_kpss_t, p_kpss_t] = kpsstest(tcr_clean);

        fprintf('Brecha del producto -> ADF:  h=%d, p=%.4f | KPSS: h=%d, p=%.4f\n', h_adf, p_adf, h_kpss, p_kpss);
        fprintf('Brecha del TCR      -> ADF:  h=%d, p=%.4f | KPSS: h=%d, p=%.4f\n', h_adf_t, p_adf_t, h_kpss_t, p_kpss_t);

        if h_adf == 0 || h_kpss == 1
            warning('[%s] La brecha del producto NO pasa las pruebas de estacionariedad de forma concluyente.', spec.nombre);
        end
        if h_adf_t == 0 || h_kpss_t == 1
            warning('[%s] La brecha del TCR NO pasa las pruebas de estacionariedad de forma concluyente.', spec.nombre);
        end
    else
        warning('[%s] adftest/kpsstest no disponibles; revisa la estacionariedad manualmente.', spec.nombre);
    end

    %% 1.3) Ensamblar X completo
    % --------------------------------------------------------------------
    X = [actividad, sub, tasa, exp, brecha_tcr];
    Xmnem   = {'brecha_igae','sub','tasa','exp','brecha_tcr'};
    Xvnames = {'Brecha del Producto','Inflaci\''on (sub)','Tasa de inter\''es','Expectativas','Brecha del TCR'};
    nvars   = size(X,2);

    
    nlags = 1;
    detc  = 1;

    %% 3) Ventanas de muestra
    % --------------------------------------------------------------------
    fecha_min_datos = dates_dt(1);
    fecha_max_datos = dates_dt(T);
    n_ventanas = numel(spec.ventana_lbl);

    idx = cell(n_ventanas,1);
    for k = 1:n_ventanas
        if spec.ventana_ini(k) < fecha_min_datos || spec.ventana_fin(k) > fecha_max_datos
            warning('[%s] Ventana %s excede el rango disponible (%s a %s); se recorta.', ...
                spec.nombre, spec.ventana_lbl{k}, datestr(fecha_min_datos,'yyyy-mm'), datestr(fecha_max_datos,'yyyy-mm'));
        end
        idx{k} = find(dates_dt >= spec.ventana_ini(k) & dates_dt <= spec.ventana_fin(k));
        if isempty(idx{k})
            error('[%s] Ventana %s no tiene observaciones disponibles.', spec.nombre, spec.ventana_lbl{k});
        end
    end

    fprintf('\n--- [%s] Ventanas de muestra (trimestral) ---\n', spec.nombre);
    for k = 1:n_ventanas
        fprintf('Ventana %d (%s): %s a %s, n = %d trimestres\n', ...
            k, spec.ventana_lbl{k}, datestr(dates_dt(idx{k}(1)),'yyyy-mm'), ...
            datestr(dates_dt(idx{k}(end)),'yyyy-mm'), length(idx{k}));
    end

    n_param_por_ecuacion = nvars*nlags + detc;
    for k = 1:n_ventanas
        if length(idx{k}) < 10*n_param_por_ecuacion
            warning('[%s] Ventana %d (%s): solo %d trimestres frente a ~%d parámetros/ecuación (regla >=10x).', ...
                spec.nombre, k, spec.ventana_lbl{k}, length(idx{k}), n_param_por_ecuacion);
        end
    end

    %% 4) Opciones generales del VAR
    % --------------------------------------------------------------------
    VARopt = VARoption;
    VARopt.vnames    = Xvnames;
    VARopt.mnem      = Xmnem;
    VARopt.nsteps    = spec.nsteps_irf;   % horizonte = horizonte de interés del modelo (12m o 4a)
    VARopt.frequency = 'q';
    VARopt.impact    = 0;
    VARopt.pctg      = spec.pctg;
    VARopt.method    = 'wild';
    VARopt.inference = 1;
    VARopt.ndraws    = spec.ndraws;
    VARopt.sr_hor    = spec.sr_hor;
    VARopt.quality   = 0;
    set(0,'DefaultFigureWindowStyle','normal');

    %% 5) Restricciones de signo
    % --------------------------------------------------------------------
    %              Demanda  Oferta  Expectativas  TipoCambio
    R = [            1,        0,        0,            1   ;    % brecha_igae
                     1,        1,        0,            0   ;    % sub
                     1,        1,        0,            0   ;    % tasa
                     0,        0,        0,            0   ;    % exp
                     0,        0,        0,            1  ];    % brecha_tcr

    VARopt.snames = {'Pol\''itica Monetaria','Demanda','Oferta','Expectativas','Tipo de Cambio'};
    VARopt.ident  = 'sign+iv';
    VARopt.R      = R;

    %% 6) Estimación por ventana
    % --------------------------------------------------------------------
    VAR_sub = cell(n_ventanas,1);
    for k = 1:n_ventanas
        fprintf('\n--- [%s] Estimando ventana %d (%s) ---\n', spec.nombre, k, spec.ventana_lbl{k});
        Xk   = X(idx{k}, :);
        mpsk = mps(idx{k});

        VARopt.IV      = mpsk;
        VARopt.figname = sprintf('graphics/svar_%s_%s', spec.nombre, strrep(spec.ventana_lbl{k}, '-', '_'));
        VAR_sub{k} = VARmodel(Xk, nlags, detc, VARopt);

        fprintf('F-stat de primera etapa (ventana %d): %.4f\n', k, VAR_sub{k}.FirstStage.F);
        if VAR_sub{k}.FirstStage.F < 10
            warning('[%s] Ventana %d (%s): F-stat de primera etapa < 10; instrumento posiblemente débil.', ...
                spec.nombre, k, spec.ventana_lbl{k});
        end
    end

    %% 7) Descomposición histórica (última ventana)
    % --------------------------------------------------------------------
    k_ultima = n_ventanas;
    VARopt.vnames  = Xvnames;
    VARopt.figname = sprintf('graphics/svar_%s_%s', spec.nombre, strrep(spec.ventana_lbl{k_ultima}, '-', '_'));
    for i = 1:nvars
        VARopt.pick = i;
        VARhdplot(VAR_sub{k_ultima}.HDfp, VARopt);
    end

    %% Empaquetar resultados
    % --------------------------------------------------------------------
    res.VAR_sub     = VAR_sub;
    res.Xvnames     = Xvnames;
    res.Xmnem       = Xmnem;
    res.nvars       = nvars;
    res.n_ventanas  = n_ventanas;
    res.ventana_lbl = spec.ventana_lbl;
    res.snames      = VARopt.snames;
    res.nsteps_irf  = spec.nsteps_irf;
end


function graficar_comparacion_choques(res, spec)
% Para el modelo dado, genera UNA figura por choque estructural, con un
% subpanel por variable de respuesta, superponiendo las IRFs de todas las
% ventanas temporales del modelo, truncadas a res.nsteps_irf horizontes.

    h_steps      = 0:(res.nsteps_irf-1);
    n_ventanas   = res.n_ventanas;
    nvars        = res.nvars;
    colores      = lines(n_ventanas);
    estilos_base = {'-','--',':','-.'};
    estilos      = estilos_base(mod(0:n_ventanas-1, numel(estilos_base)) + 1);

    for s = 1:nvars
        fig = figure('Name', sprintf('%s -- Choque: %s', spec.label, res.snames{s}));

        for i = 1:nvars
            subplot(ceil(nvars/2), 2, i); hold on;

            h_lines = gobjects(n_ventanas,1);
            for k = 1:n_ventanas
                IRinf_k = squeeze(res.VAR_sub{k}.IRinf(:,i,s));
                IRsup_k = squeeze(res.VAR_sub{k}.IRsup(:,i,s));
                IRmed_k = squeeze(res.VAR_sub{k}.IRmed(:,i,s));

                fill([h_steps, fliplr(h_steps)], ...
                     [IRinf_k', fliplr(IRsup_k')], ...
                     colores(k,:), 'FaceAlpha', 0.12, 'EdgeColor', 'none');
                h_lines(k) = plot(h_steps, IRmed_k, ...
                     'Color', colores(k,:), 'LineWidth', 1.8, 'LineStyle', estilos{k});
            end

            yline(0, 'k:', 'LineWidth', 0.8);
            title(res.Xvnames{i}, 'Interpreter', 'latex');
            xlabel('Trimestres'); grid on;
            if i == 1
                legend(h_lines, res.ventana_lbl, 'Location', 'best', 'FontSize', 7);
            end
        end

        sgtitle(sprintf('Respuesta a un choque de %s -- %s (horizonte: %s)', ...
            res.snames{s}, spec.label, spec.horiz_label), 'Interpreter', 'latex');

        fname = sprintf('graphics/svar_%s_choque_%d_comparacion_ventanas.pdf', spec.nombre, s);
        print(fig, '-dpdf', fname);
    end
end
