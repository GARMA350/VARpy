%% ========================================================================
%  SVAR con identificación mixta: Instrumentos Externos + Restricciones de Signo
%  + BLOQUE EXÓGENO DE EUA (bp_eua, pi_EU, ffr)
%  Método: Cesa-Bianchi & Sokol (2021), implementado en el VAR Toolbox
%  (Cesa-Bianchi) mediante VARopt.ident = 'sign+iv'
%
%  ADAPTACIÓN respecto al script original (svar_expectativas):
%   1) Fuente de datos: datospy_modelo_expectativas.xlsx, frecuencia MENSUAL.
%      Columnas: Fecha, bp_eua, pi_EU, ffr, bp, pi, i, exp12m, exp4a, exp8a, b_tcr
%   2) bp_eua, pi_EU, ffr entran como BLOQUE EXÓGENO (EXOG), no endógeno:
%      per las reglas de este proyecto, EXOG es control de forma reducida
%      puro -> no genera IRFs/FEVD/HD propios y no participa en la
%      identificación estructural (ver learnings-and-ways-of-working).
%   3) bp, pi, i, exp12m, exp4a, exp8a, b_tcr ya vienen como brechas /
%      tasas (no niveles crudos) -> NO se vuelve a aplicar filtro HP aquí.
%      Si tu archivo cambia a niveles crudos, reincorpora el filtro HP de
%      la sección 1.1 del script original.
%   4) *** PENDIENTE / ACCIÓN REQUERIDA ***: este archivo NO trae el
%      instrumento externo `mps` (sorpresas de política monetaria) que
%      identifica el choque 1 bajo 'sign+iv'. Sin `mps`, VARopt.ident =
%      'sign+iv' no puede estimarse. Se deja un bloque claramente marcado
%      en la Sección 1 para que cargues y fusiones `mps` desde tu archivo
%      original (BaseDatosMensual.xlsx) por fecha. Mientras tanto, el
%      script usa un vector de NaN como placeholder y se detendrá con un
%      error explícito si intentas estimar sin reemplazarlo.
%   5) EXOG (dummies de outliers + bloque EUA) se pasa como QUINTO
%      argumento posicional de VARmodel, con nlag_ex = 0, siguiendo la
%      convención ya usada en el proyecto para el bloque EUA.
%   6) El bloque EUA SÍ incluye rezagos (controlado por `nlag_ex_eua` en
%      la Sección 1.3b): se construyen a mano [EUA(t),...,EUA(t-p)] y se
%      concatenan con las dummies (sin rezagar), pasando nlag_ex=0 a
%      VARmodel para no rezagar también las dummies. Ver 1.3b para la
%      alternativa de usar el nlag_ex nativo del toolbox sobre todo EXOG.
% ========================================================================

clear; clc; close all;

addpath(genpath("C:\Users\K21168\Desktop\VARtoolbox"))

%% 1) Cargar datos
% ------------------------------------------------------------------------
% Encabezados esperados: Fecha, bp_eua, pi_EU, ffr, bp, pi, i, exp12m, exp4a, exp8a, b_tcr
Ttab = readtable("C:\Users\K21168\Desktop\modelo_expectativas\SVAR\Datos\datospy_modelo_expectativas.xlsx");

dates_dt = datetime(Ttab.Fecha);   % fechas mensuales

% --- Bloque EXÓGENO (EUA) ---
bp_eua  = Ttab.bp_eua;    % brecha del producto de EUA (ya calculada)
pi_eua  = Ttab.pi_EU;     % inflación de EUA
ffr     = Ttab.ffr;       % tasa de fondos federales

% --- Bloque ENDÓGENO (México) ---
bp      = Ttab.bp;        % brecha del producto de México (ya calculada)
pinf    = Ttab.pi;        % inflación de México
i_tasa  = Ttab.i;         % tasa de interés de México
exp12   = Ttab.exp12m;    % expectativas de inflación 12m
exp4    = Ttab.exp4a;     % expectativas de inflación 4a
exp8    = Ttab.exp8a;     % expectativas de inflación 8a
b_tcr   = Ttab.b_tcr;     % brecha del tipo de cambio real (ya calculada)
mps = Ttab.MPS6; 
T = height(Ttab);

% *** PENDIENTE: instrumento externo mps ***
% Este archivo (datospy_modelo_expectativas.xlsx) no trae `mps`.
% Sustituye este bloque por la carga real y el merge por fecha con tu
% archivo original, p.ej.:
%
%   Tmps = readtable("C:\Users\K21168\Desktop\modelo_expectativas\SVAR\Datos\BaseDatosMensual.xlsx");
%   dates_mps = datetime(Tmps.Fecha);
%   [~, ia, ib] = intersect(dates_dt, dates_mps, 'stable');
%   mps = nan(T,1);
%   mps(ia) = Tmps.mps3(ib);
%
   % <-- PLACEHOLDER: reemplazar antes de estimar

mnem_exog = {'bp_eua','pi_eua','ffr'};
mnem_endo = {'bp','pi','i','exp12','exp4','exp8','b_tcr'};

%% 1.0) Gráfica exploratoria de las series originales (endógenas + EXOG)
% ------------------------------------------------------------------------
fig_raw = figure('Name','Series originales (mensual)');
vars_raw  = {bp, pinf, i_tasa, exp12, exp4, exp8, b_tcr, bp_eua, pi_eua, ffr};
names_raw = {'Brecha del producto (Mex)','Inflacion (Mex)','Tasa de interes (Mex)', ...
             'Exp. Inflacion 12m','Exp. Inflacion 4a','Exp. Inflacion 8a','Brecha del TCR', ...
             'Brecha del producto (EUA)','Inflacion (EUA)','Fed Funds Rate'};
n_raw = numel(vars_raw);

for k = 1:n_raw
    subplot(ceil(n_raw/2), 2, k);
    plot(dates_dt, vars_raw{k}, 'LineWidth', 1.2);
    title(names_raw{k}, 'Interpreter', 'latex');
    xlabel('Fecha'); grid on;
end
sgtitle('Series originales (endogenas + bloque EXOG de EUA)', 'Interpreter', 'latex');

if ~exist('graphics', 'dir'); mkdir('graphics'); end
print(fig_raw, '-dpdf', 'graphics/series_originales_mensual_exog.pdf');

%% 1.1) Transformaciones
% ------------------------------------------------------------------------
% bp, b_tcr y bp_eua llegan YA como brechas (no se vuelve a aplicar HP).
% pi, i, exp12m, exp4a, exp8a, pi_EU, ffr llegan ya en niveles/tasas
% comparables (%). No se aplican transformaciones adicionales.
%
% Si en algún momento el archivo vuelve a traer niveles crudos (p.ej. un
% índice de actividad en vez de la brecha ya calculada), reincorpora aquí
% el filtro HP con lambda_hp = 14400 (mensual, Ravn-Uhlig), tal como en el
% script original:
%
%   log_x = log(x);
%   [x_trend, x_cycle] = hpfilter(log_x, 'Smoothing', 14400);
%   brecha_x = x_cycle;

actividad  = bp;
brecha_tcr = b_tcr;

%% 1.2) Chequeo de estacionariedad (ADF + KPSS): endógenas, EXOG e instrumento
% ------------------------------------------------------------------------
series_test = {actividad, pinf, i_tasa, exp12, exp4, exp8, brecha_tcr, bp_eua, pi_eua, ffr, mps};
label_test  = {'Brecha del producto (Mex)', 'Inflaci\''on (Mex)', 'Tasa de inter\''es (Mex)', ...
               'Exp. Inflaci\''on 12m', 'Exp. Inflaci\''on 4a','Exp. Inflaci\''on 8a', 'Brecha del TCR', ...
               'Brecha del producto (EUA)','Inflaci\''on (EUA)','Fed Funds Rate','mps (instrumento)'};
name_test   = {'bp','pi','i','exp12','exp4','exp8','b_tcr','bp_eua','pi_eua','ffr','mps'};

nseries = numel(series_test);
ADF_h  = nan(nseries,1); ADF_p  = nan(nseries,1);
KPSS_h = nan(nseries,1); KPSS_p = nan(nseries,1);

if exist('adftest','file') == 2 && exist('kpsstest','file') == 2
    for k = 1:nseries
        s = series_test{k};
        s_clean = s(~isnan(s));
        if numel(s_clean) < 10
            fprintf('%-14s -> muestra insuficiente para ADF/KPSS (n=%d), se omite.\n', name_test{k}, numel(s_clean));
            continue
        end

        [ADF_h(k), ADF_p(k)]   = adftest(s_clean);
        [KPSS_h(k), KPSS_p(k)] = kpsstest(s_clean);

        fprintf('%-14s -> ADF:  h = %d (1=estacionaria), p = %.4f | KPSS: h = %d (0=estacionaria), p = %.4f\n', ...
            name_test{k}, ADF_h(k), ADF_p(k), KPSS_h(k), KPSS_p(k));

        if ADF_h(k) == 0 || KPSS_h(k) == 1
            warning(['La serie "%s" (%s) NO pasa las pruebas de estacionariedad de ' ...
                     'forma concluyente. Revisa la transformaci\''on o considera ' ...
                     'diferenciar/ajustar antes de usarla en el VAR/EXOG.'], name_test{k}, label_test{k});
        end
    end

    StationarityResults = table(name_test', ADF_h, ADF_p, KPSS_h, KPSS_p, ...
        'VariableNames', {'Serie','ADF_h','ADF_p','KPSS_h','KPSS_p'});
    disp(StationarityResults);
else
    warning(['adftest/kpsstest no disponibles (requieren Econometrics ' ...
              'Toolbox); revisa la estacionariedad de las series manualmente ' ...
              'antes de confiar en los resultados del VAR.']);
end

%% 1.3) Ensamblar X (endógenas) y EXOG_EUA (exógenas, EUA)
% ------------------------------------------------------------------------
X = [actividad, pinf, i_tasa, exp12, exp4, exp8, brecha_tcr];
Xmnem   = {'bp','pi','i','exp12','exp4','exp8','b_tcr'};
Xvnames = {'Brecha del Producto (Mex)','Inflacion','Tasa de interes', ...
           'Exp. Inflacion 12m','Exp. Inflacion 4a','Exp. Inflacion 8a','Brecha del TCR'};

EXOG_EUA = [bp_eua, pi_eua, ffr];
EXOGmnem = {'bp_eua','pi_eua','ffr'};

nvars     = size(X,2);
nexog_eua = size(EXOG_EUA,2);

%% 1.3b) Rezagos opcionales del bloque EXOG de EUA
% ------------------------------------------------------------------------
% Dos rutas para incluir REZAGOS de bp_eua, pi_eua, ffr (no solo el valor
% contemporáneo):
%
%  A) nlag_ex NATIVO de VARmodel (sexto argumento posicional): arma
%     internamente [EXOG(t),...,EXOG(t-nlag_ex)]. Problema: nlag_ex se
%     aplica a TODO lo que entra por el quinto argumento -> si ahí también
%     van las dummies de outliers (como en este script), también se
%     generarían rezagos de las dummies (columnas casi todo cero: no
%     rompe la estimación, pero gasta grados de libertad de más).
%
%  B) Construir los rezagos SOLO del bloque EUA aquí, a mano, y pasar
%     nlag_ex = 0 a VARmodel (los rezagos ya están explícitos en la
%     matriz). Las dummies de outliers se concatenan SIN rezagar, como
%     antes. Esta es la ruta usada por defecto en este script: da control
%     total y evita rezagar dummies innecesariamente. Nota: como el
%     script se corre por secciones (no como función completa), no se usa
%     una función local para construir los rezagos, per la convención del
%     proyecto — es un loop inline.
%
% Ajusta nlag_ex_eua para cambiar cuántos rezagos de EUA entran (0 = solo
% contemporáneo, equivalente al script anterior).
nlag_ex_eua = 1;   % <-- número de rezagos del bloque EUA

EXOG_EUA_lags = nan(T, nexog_eua*(nlag_ex_eua+1));
EXOGmnem_lags = cell(1, nexog_eua*(nlag_ex_eua+1));
for L = 0:nlag_ex_eua
    cols = (L*nexog_eua+1):(L+1)*nexog_eua;
    EXOG_EUA_lags(L+1:T, cols) = EXOG_EUA(1:T-L, :);   % filas 1..L quedan en NaN, se recortan en Secc. 6/9
    for j = 1:nexog_eua
        if L == 0
            EXOGmnem_lags{cols(j)} = EXOGmnem{j};
        else
            EXOGmnem_lags{cols(j)} = sprintf('%s_L%d', EXOGmnem{j}, L);
        end
    end
end

nexog_eua_total = size(EXOG_EUA_lags, 2);   % columnas totales del bloque EUA (contemp. + rezagos)

%% 2) Selección de rezagos (sobre la muestra completa)
% ------------------------------------------------------------------------
%{
pmax = 12;
disp('--- Selección de rezagos (criterios de información, muestra completa) ---')
[lag_AIC, lag_BIC, ~] = VARlag(X, pmax, 1);
fprintf('Rezago óptimo según AIC: %d\n', lag_AIC);
fprintf('Rezago óptimo según BIC: %d\n', lag_BIC);
%}
nlags = 2;               % <-- AJUSTA con base en el resultado de VARlag
detc  = 1;               % 1 = constante

%% 1.4) Dummies de periodos atípicos
% ------------------------------------------------------------------------
DUM_2004_2004 = zeros(T,1);
DUM_2004_2004(isbetween(dates_dt, datetime(2004,8,1), datetime(2004,12,1))) = 1;

DUM_covid = zeros(T,1);
DUM_covid(isbetween(dates_dt, datetime(2020,3,1), datetime(2020,5,1))) = 1;
if sum(DUM_covid) ~= 2
    warning(['La dummy COVID no encontró exactamente 2 meses (encontró %d). ' ...
        'Revisa dates_dt.'], sum(DUM_covid));
end

DUM_2008_2009 = zeros(T,1);
DUM_2008_2009(isbetween(dates_dt, datetime(2009,1,1), datetime(2009,4,1))) = 1;

DUM_2011_2011 = zeros(T,1);
DUM_2011_2011(isbetween(dates_dt, datetime(2011,9,1), datetime(2011,9,1))) = 1;

DUM_2011_2012 = zeros(T,1);
DUM_2011_2012(isbetween(dates_dt, datetime(2012,6,1), datetime(2012,9,1))) = 1;

DUM_2017_2017 = zeros(T,1);
DUM_2017_2017(isbetween(dates_dt, datetime(2017,1,1), datetime(2017,1,1))) = 1;

DUM_2024_2024 = zeros(T,1);
DUM_2024_2024(isbetween(dates_dt, datetime(2024,8,1), datetime(2024,9,1))) = 1;

% Matriz combinada de dummies (T x 5), mismo orden que el script original.
DUM_all = [DUM_2008_2009, DUM_covid];
nombres_dum = {'2008-2009','COVID'};

fecha_min_datos = dates_dt(1);
fecha_max_datos = dates_dt(T);

%% 3) Definición de las ventanas de muestra
% ------------------------------------------------------------------------
n_ventanas = 1;
ventana_ini = datetime(2009,1,1);
ventana_fin = datetime(2026,12,30);
ventana_lbl = {'2009-2026'};
idx = cell(n_ventanas,1);
for k = 1:n_ventanas
    if ventana_ini(k) < fecha_min_datos || ventana_fin(k) > fecha_max_datos
        warning(['Ventana %s excede el rango disponible en los datos (%s a %s). ' ...
                 'Se recortará automáticamente a lo disponible.'], ...
                 ventana_lbl{k}, datestr(fecha_min_datos, 'yyyy-mm'), datestr(fecha_max_datos, 'yyyy-mm'));
    end
    idx{k} = find(dates_dt >= ventana_ini(k) & dates_dt <= ventana_fin(k));
    if isempty(idx{k})
        error('Ventana %s no tiene observaciones dentro del rango de datos disponible.', ventana_lbl{k});
    end
end

fprintf('\n--- Ventanas de muestra (mensual) ---\n');
for k = 1:n_ventanas
    fprintf('Ventana %d (solicitada %s): %s a %s, n = %d meses\n', ...
        k, ventana_lbl{k}, datestr(dates_dt(idx{k}(1)), 'yyyy-mm'), ...
        datestr(dates_dt(idx{k}(end)), 'yyyy-mm'), length(idx{k}));
end

% Chequeo de tamaño de muestra vs. parámetros estimados
% (incluye columnas de EXOG_EUA YA REZAGADAS, per la regla del proyecto de
%  actualizar n_param_por_ecuacion cuando cambia el bloque exógeno)
n_param_por_ecuacion = nvars*nlags + detc + nexog_eua_total;
for k = 1:n_ventanas
    if length(idx{k}) < 10*n_param_por_ecuacion
        warning(['Ventana %d (%s) tiene solo %d meses frente a ~%d parámetros por ecuación ' ...
                 '(incl. EXOG EUA; regla informal >= 10x). Resultados potencialmente poco confiables.'], ...
                 k, ventana_lbl{k}, length(idx{k}), n_param_por_ecuacion);
    end
end

%% 4) Opciones generales del VAR (compartidas por todas las ventanas)
% ------------------------------------------------------------------------
VARopt = VARoption;
VARopt.vnames    = Xvnames;
VARopt.mnem      = Xmnem;
VARopt.nsteps    = 40;         % horizonte de los IRF: 40 MESES
VARopt.frequency = 'm';        % mensual
VARopt.impact    = 0;
VARopt.pctg      = 68;
VARopt.method    = 'wild';
VARopt.inference = 1;
VARopt.ndraws    = 1000;
VARopt.sr_draw   = 10000000;
VARopt.sr_hor    = 4;
set(0,'DefaultFigureWindowStyle','normal');
VARopt.quality   = 0;

%     Dm Of E12 E4 E8 Tc
R = [ 1, -1, 0, 0, 0, 0;    % bp (brecha del producto)
      1,  1, 0, 0, 0, 0;    % pi (inflacion)
      1,  0, 0, 0, 0, 0;    % i (tasa)
      0,  0, 0, 0, 0, 0;    % exp12
      0,  0, 0, 0, 0, 0;    % exp4
      0,  0, 0, 0, 0, 0;    % exp8
      0,  0, 0, 0, 0, 1 ];  % b_tcr

%% 5) Restricciones de signo para los 6 choques NO identificados por IV
% ------------------------------------------------------------------------
VARopt.snames = {'Pol\''itica Monetaria','Demanda','Oferta','Exp12','Exp4','Exp8','Tipo de Cambio'};
VARopt.ident  = 'sign+iv';
VARopt.R      = R;

%% 6) Estimación por ventana (EXOG = dummies + bloque EUA)
% ------------------------------------------------------------------------
VAR_sub = cell(n_ventanas,1);

for k = 1:n_ventanas
    fprintf('\n--- Estimando ventana %d/%d (%s) ---\n', k, n_ventanas, ventana_lbl{k});
    Xk    = X(idx{k}, :);
    mpsk  = mps(idx{k});

    if all(isnan(mpsk))
        error(['mps no ha sido cargado (placeholder de NaN). Ver la Sección 1: ' ...
               'carga y fusiona el instrumento externo desde tu archivo original ' ...
               '(BaseDatosMensual.xlsx) antes de estimar el modelo IV+sign.']);
    end

    DUMk_full = DUM_all(idx{k}, :);
    EUAk      = EXOG_EUA_lags(idx{k}, :);

    % 1) Recortar primero por NaN
    fila_completa = all(~isnan([Xk, mpsk, DUMk_full, EUAk]), 2);
    if any(~fila_completa)
        fprintf('Meses recortados: %s\n', ...
            strjoin(cellstr(datestr(dates_dt(idx{k}(~fila_completa)), 'yyyy-mm')), ', '));
    end
    Xk        = Xk(fila_completa, :);
    mpsk      = mpsk(fila_completa);
    DUMk_full = DUMk_full(fila_completa, :);
    EUAk      = EUAk(fila_completa, :);
    
    % 2) Dummies activas en la muestra EFECTIVA de OLS (sin las primeras nlags filas)
    cols_activas = any(DUMk_full(nlags+1:end, :) ~= 0, 1);
    DUMk = DUMk_full(:, cols_activas);
    if any(~cols_activas)
        fprintf('Se excluyen dummies sin observaciones: %s\n', ...
            strjoin(nombres_dum(~cols_activas), ', '));
    end
    
EXOGk = [DUMk, EUAk];

% 3) Chequeo de rango antes de estimar
Z = [ones(size(Xk,1),1), lagmatrix(Xk, 1:nlags), EXOGk];
Z = Z(nlags+1:end, :);
fprintf('Rango regresores: %d de %d columnas\n', rank(Z), size(Z,2));
if rank(Z) < size(Z,2)
    error('Regresores colineales: revisa EXOGk (dummies o bloque EUA).');
end

    VARopt.IV        = mpsk;
    VARopt.vnames_ex = [nombres_dum(cols_activas), EXOGmnem_lags];
    VARopt.figname   = sprintf('graphics/svar_sign_iv_exog_eua_%s', strrep(ventana_lbl{k}, '-', '_'));
    % EXOG (dummies + bloque EUA ya rezagado) como quinto argumento;
    % nlag_ex = 0 porque los rezagos del bloque EUA ya están embebidos en
    % EXOGk (ruta B de 1.3b) — VARmodel no vuelve a rezagar nada.
    % Control de forma reducida: sin IRFs/FEVD/HD propios.
    VAR_sub{k} = VARmodel(Xk, nlags, detc, VARopt, EXOGk, 0);

    % --- Chequeo de estabilidad (eigenvalues de la matriz companion) ---
    maxEig_k = VAR_sub{k}.maxEig;

    if maxEig_k < 1
        estado_str = 'ESTABLE';
    else
        estado_str = 'INESTABLE';
    end

    fprintf('Ventana %d (%s): max|eigenvalue| = %.4f -> VAR %s\n', ...
        k, ventana_lbl{k}, maxEig_k, estado_str);

    if maxEig_k >= 1
        warning(['Ventana %d (%s): el VAR es INESTABLE (max|eigenvalue| = %.4f >= 1). ' ...
                 'Los IRFs, FEVD y HD de esta ventana no est\''an bien definidos.'], ...
                 k, ventana_lbl{k}, maxEig_k);
    end

    % --- F-stat de primera etapa ---
    fprintf('F-stat de primera etapa (ventana %d): %.4f\n', k, VAR_sub{k}.FirstStage.F);
    if VAR_sub{k}.FirstStage.F < 10
        warning('Ventana %d (%s): F-stat de primera etapa < 10; instrumento posiblemente débil en este periodo (recalcular tras cualquier cambio en EXOG, per convención del proyecto).', ...
            k, ventana_lbl{k});
    end
end

%% 6.1) Resumen de estabilidad y fuerza del instrumento por ventana
% ------------------------------------------------------------------------
maxEig_all  = cellfun(@(v) v.maxEig, VAR_sub);
Fstat_all   = cellfun(@(v) v.FirstStage.F, VAR_sub);
estable_all = maxEig_all < 1;

StabilitySummary = table(ventana_lbl(:), maxEig_all, estable_all, Fstat_all, ...
    'VariableNames', {'Ventana','MaxEigenvalue','Estable','F_stat_1a_etapa'});
disp(StabilitySummary);

%% 7) IRFs individuales de cada ventana (choque 1 = política monetaria)
% ------------------------------------------------------------------------
VARopt.pick = 1;
for k = 1:n_ventanas
    VARopt.figname = sprintf('graphics/svar_sign_iv_exog_eua_%s', strrep(ventana_lbl{k}, '-', '_'));
    VARirplot(VAR_sub{k}.IRmed, VARopt, VAR_sub{k}.IRinf, VAR_sub{k}.IRsup);
end

%% 7.1) IRFs completas (los 7 choques) para la ÚLTIMA ventana
% ------------------------------------------------------------------------
k_ultima = n_ventanas;
VARopt.figname = sprintf('graphics/svar_sign_iv_exog_eua_%s', strrep(ventana_lbl{k_ultima}, '-', '_'));
for s = 1:nvars
    VARopt.pick = s;
    VARirplot(VAR_sub{k_ultima}.IRmed, VARopt, VAR_sub{k_ultima}.IRinf, VAR_sub{k_ultima}.IRsup);
end

%% 8) Gráfica comparativa: IRF de política monetaria, todas las ventanas
% ------------------------------------------------------------------------
h_steps = 0:(VARopt.nsteps-1);
colores = parula(n_ventanas);
estilo  = '-';

fig_comp = figure('Name', 'Comparación IRF: Política Monetaria (mensual, con EXOG EUA)');
for i = 1:nvars
    subplot(ceil(nvars/2), 2, i); hold on;

    h_lines = gobjects(n_ventanas,1);
    for k = 1:n_ventanas
        h_lines(k) = plot(h_steps, squeeze(VAR_sub{k}.IRmed(:,i,1)), ...
             'Color', colores(k,:), 'LineWidth', 1.5, 'LineStyle', estilo);
    end

    yline(0, 'k:', 'LineWidth', 0.8);
    title(Xvnames{i}, 'Interpreter', 'latex');
    xlabel('Meses'); grid on;
    if i == 1
        if n_ventanas <= 6
            legend(h_lines, ventana_lbl, 'Location', 'best', 'FontSize', 7);
        else
            colormap(gca, colores);
            cb = colorbar('Ticks', linspace(0,1,n_ventanas), ...
                           'TickLabels', ventana_lbl, 'FontSize', 6);
            cb.Label.String = 'Ventana';
        end
    end
end
sgtitle('Respuesta a un choque de Pol\''itica Monetaria (bloque EXOG de EUA)', 'Interpreter', 'latex');

if ~exist('graphics', 'dir'); mkdir('graphics'); end
print(fig_comp, '-dpdf', 'graphics/svar_sign_iv_exog_eua_comparacion_ventanas.pdf');

%% 9) IRFs con bandas de confianza 68% y 90% superpuestas
% ------------------------------------------------------------------------
generar_bandas_68_90 = true;
ventanas_a_graficar  = 1:n_ventanas;

if generar_bandas_68_90
fprintf('\nSección 9 generará %d figuras (%d ventanas x %d choques).\n', ...
    numel(ventanas_a_graficar)*nvars, numel(ventanas_a_graficar), nvars);

VARopt_68 = VARopt; VARopt_68.pctg = 68;
VARopt_90 = VARopt; VARopt_90.pctg = 90;

VAR_68 = cell(n_ventanas,1);
VAR_90 = cell(n_ventanas,1);

for k = ventanas_a_graficar
    fprintf('\n--- Recalculando bandas 68%% y 90%% para ventana %d (%s) ---\n', k, ventana_lbl{k});
    Xk   = X(idx{k}, :);
    mpsk = mps(idx{k});

    DUMk_full    = DUM_all(idx{k}, :);
    cols_activas = any(DUMk_full ~= 0, 1);
    DUMk         = DUMk_full(:, cols_activas);

    EUAk  = EXOG_EUA_lags(idx{k}, :);   % ya incluye contemporáneo + nlag_ex_eua rezagos
    EXOGk = [DUMk, EUAk];
    fila_completa = all(~isnan([Xk, mpsk, EXOGk]), 2);
    Xk    = Xk(fila_completa, :);
    mpsk  = mpsk(fila_completa);
    EXOGk = EXOGk(fila_completa, :);

    VARopt_68.IV = mpsk;
    VARopt_90.IV = mpsk;

    VAR_68{k} = VARmodel(Xk, nlags, detc, VARopt_68, EXOGk, 0);
    VAR_90{k} = VARmodel(Xk, nlags, detc, VARopt_90, EXOGk, 0);
end

%% 9.1) Gráfica: un figure por ventana, subpanel por variable, todos los choques
% ------------------------------------------------------------------------
h_steps = 0:(VARopt.nsteps-1);
color_90 = [0.30 0.30 0.30];
color_68 = [0.10 0.35 0.75];

for k = ventanas_a_graficar
    for s = 1:nvars

        fig_conf = figure('Name', sprintf('IRF - Choque %s - Bandas 68%%/90%% (%s)', ...
            VARopt.snames{s}, ventana_lbl{k}));

        for i = 1:nvars

            subplot(ceil(nvars/2), 2, i); hold on;

            med  = squeeze(VAR_68{k}.IRmed(:, i, s));
            lo90 = squeeze(VAR_90{k}.IRinf(:, i, s));
            hi90 = squeeze(VAR_90{k}.IRsup(:, i, s));
            lo68 = squeeze(VAR_68{k}.IRinf(:, i, s));
            hi68 = squeeze(VAR_68{k}.IRsup(:, i, s));

            fill([h_steps, fliplr(h_steps)], [lo90', fliplr(hi90')], ...
                 color_90, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
            fill([h_steps, fliplr(h_steps)], [lo68', fliplr(hi68')], ...
                 color_68, 'FaceAlpha', 0.30, 'EdgeColor', 'none');
            plot(h_steps, med, 'Color', color_68, 'LineWidth', 1.8);

            yline(0, 'k:', 'LineWidth', 0.8);
            title(Xvnames{i}, 'Interpreter', 'latex');
            xlabel('Meses'); grid on;

            if i == 1
                h_leg90 = fill(nan, nan, color_90, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
                h_leg68 = fill(nan, nan, color_68, 'FaceAlpha', 0.30, 'EdgeColor', 'none');
                legend([h_leg90, h_leg68], {'90%', '68%'}, 'Location', 'best', 'FontSize', 7);
            end
        end

        sgtitle(sprintf('Respuesta a choque de %s (%s): bandas 68%% y 90%% [EXOG EUA]', ...
            VARopt.snames{s}, ventana_lbl{k}), 'Interpreter', 'latex');

        if ~exist('graphics', 'dir'); mkdir('graphics'); end
        nombre_choque = strrep(strrep(VARopt.snames{s}, ' ', '_'), '\''', '');
        print(fig_conf, '-dpdf', sprintf('graphics/svar_sign_iv_exog_eua_%s_choque_%s_bandas68_90.pdf', ...
            strrep(ventana_lbl{k}, '-', '_'), nombre_choque));
    end
end
end % if generar_bandas_68_90