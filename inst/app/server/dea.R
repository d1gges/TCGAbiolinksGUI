# -------------------------------------------------
# DEA
# -------------------------------------------------
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
# Handling visibility
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
observeEvent(input$deanormalization, {
    shinyjs::toggle("deanormalizationmet")
})
observeEvent(input$deafilter, {
    shinyjs::toggle("deafilteringmet")
    shinyjs::toggle("deafilteringcut")
})
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
# Analysis
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=

observeEvent(input$deaAnalysis , {
    closeAlert(session, "deaAlert")
    # read the data from the downloaded path
    # prepare it
    se <- isolate({deadata()})
    if(is.null(se)) return(NULL)

    groupCol <-  isolate({input$deagroupCol})

    if(stringr::str_length(groupCol) == 0){
        createAlert(session, "deamessage", "deaAlert", title = "Group input error", style =  "danger",
                    content = paste0("Please, select the groupCol argument"), append = FALSE)
        return(NULL)
    }

    g1 <- isolate({input$deagroup1})
    g2 <- isolate({input$deagroup2})

    if(stringr::str_length(g1) == 0){
        createAlert(session, "deamessage", "deaAlert", title = "Group input error", style =  "danger",
                    content = paste0("Please, select the group1 argument"), append = FALSE)
        return(NULL)
    }

    if(stringr::str_length(g2) == 0){
        createAlert(session, "deamessage", "deaAlert", title = "Group input error", style =  "danger",
                    content = paste0("Please, select the group2 argument"), append = FALSE)
        return(NULL)
    }



    idx.g1 <- which(colData(se)[,groupCol] == g1)
    samples.g1 <- colData(se)[idx.g1,"barcode"]
    idx.g2 <- which(colData(se)[,groupCol] == g2)
    samples.g2 <- colData(se)[idx.g2,"barcode"]
    method <- isolate({input$deamethod})
    fdr.cut <- isolate({input$deapvalue})
    logFC.cut <- isolate({input$deathrsld})


    if(length(samples.g1) < 2) {
        createAlert(session, "deamessage", "deaAlert", title = "Error", style =  "danger",
                    content = paste0("We don't have enough samples for group ", g1, "(n = ",length(samples.g1)," )"), append = FALSE)
        return(NULL)
    }

    if(length(samples.g2) < 2) {
        createAlert(session, "deamessage", "deaAlert", title = "Error", style =  "danger",
                    content = paste0("We don't have enough samples for group ", g2, "(n = ",length(samples.g2)," )"), append = FALSE)
        return(NULL)
    }

    withProgress(message = 'Differential Expression Analysis in progress',
                 detail = 'This may take a while...', value = 0, {

                     # normalization of genes
                     if(isolate({input$deanormalization})) {
                         if(all(grepl("ENS",rownames(se)))){
                             geneInfo <- TCGAbiolinks::geneInfoHT
                         } else {
                             geneInfo <- TCGAbiolinks::geneInfo
                         }
                         incProgress(1/5, detail = paste0('normalization mRNA transcripts and miRNA using EDASeq package'))
                         exp <- TCGAanalyze_Normalization(tabDF = assay(se),
                                                          geneInfo = geneInfo,
                                                          method = isolate({input$deanormalizationmet})
                         )
                     } else {
                         exp <- assay(se)
                     }
                     # quantile filter of genes
                     if(isolate({input$deafilter})) {
                         incProgress(1/5, detail = paste0('Filtering mRNA transcripts and miRNA'))

                         dataFilt <- TCGAanalyze_Filtering(tabDF = exp,
                                                           method = isolate({input$deafilteringmet}),
                                                           qnt.cut =  isolate({input$deafilteringcut}))
                     } else {
                         dataFilt <- exp
                     }

                     incProgress(1/5, detail = paste0('Differentially expression analysis (DEA) using edgeR'))
                     exp <- TCGAanalyze_DEA(mat1 = dataFilt[,samples.g1],
                                            mat2 = dataFilt[,samples.g2],
                                            Cond1type = g1 ,
                                            Cond2type = g2,
                                            method = method)

                     incProgress(1/5, detail = paste0('Adding information related to DEGs genes from DEA'))
                     exp <- TCGAanalyze_LevelTab(exp,
                                                 typeCond1 = g1,
                                                 typeCond2 = g2,
                                                 TableCond1 = dataFilt[,samples.g1],
                                                 TableCond2 = dataFilt[,samples.g2])


                     exp$status <- "Insignificant"
                     exp[exp$logFC >= logFC.cut & exp$FDR <= fdr.cut,"status"] <- paste0("Upregulated in ", g2)
                     exp[exp$logFC <= -logFC.cut & exp$FDR <= fdr.cut,"status"] <- paste0("Downregulated in ", g2)
                     if(all(grepl("\\|",exp$mRNA))) {
                         exp$exp$mRNA <- unlist(lapply(strsplit(exp$mRNA,"\\|"),function(x) x[2]))
                     }
                     colnames(exp)[grep("mRNA",colnames(exp))] <- "Gene_symbol"
                     incProgress(1/5, detail = paste0('Saving results'))
                 })

    out.filename <- paste0(paste("DEA_results",gsub("_",".",groupCol),
                                 gsub("[[:punct:]]| ", ".",g1), gsub("[[:punct:]]| ", ".",g2),
                                 "pcut",fdr.cut,"logFC.cut",logFC.cut,sep="_"),".csv")
    getPath <- parseDirPath(get.volumes(isolate({input$workingDir})), input$workingDir)
    if (length(getPath) == 0) getPath <- paste0(Sys.getenv("HOME"),"/TCGAbiolinksGUI")
    out.filename <- file.path(getPath,out.filename)
    write_csv(exp, path = out.filename)


    #=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
    # TABLE
    #=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=

    output$deaSE <- DT::renderDataTable({
        createTable(exp)
    })

    updateCollapse(session, "collapsedea", open = "Genes info")

    createAlert(session, "deamessage", "deaAlert", title = "DEA completed", style =  "success",
                content = out.filename, append = FALSE)
})
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
# File selection
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
observe({
    shinyFileChoose(input,
                    'deafile',
                    roots = get.volumes(input$workingDir),
                    session = session,
                    restrictions = system.file(package='base'),
                    filetypes = c('','rda'))
})
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
# DATA INPUT
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
deadata <- function(){
    inFile <- input$deafile
    if(class(inFile) != "list") return(NULL)
    file  <- as.character(parseFilePaths(get.volumes(isolate({input$workingDir})), input$deafile)$datapath)
    se <- get(load(file))

    if(class(se)!= class(as(SummarizedExperiment(),"RangedSummarizedExperiment"))){
        createAlert(session, "deamessage", "deaAlert", title = "Data input error", style =  "danger",
                    content = paste0("Sorry, but I'm expecting a Summarized Experiment object, but I got a: ",
                                     class(se)), append = FALSE)
        return(NULL)
    }

    createAlert(session, "deamessage", "deaAlert", title = "Successful data import", style =  "info",
                content = paste0("Read file:", file), append = FALSE)
    return(se)
}
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
# UPDATING FIELDS AFTER DATA INPUT
#=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=
observeEvent(input$deagroupCol , {
    updateSelectizeInput(session, 'deagroup1', choices = {
        if (class(deadata()) == class(as(SummarizedExperiment(),"RangedSummarizedExperiment"))){
            if (!is.null(deadata()) & input$deagroupCol != "" )
                as.character(colData(deadata())[,input$deagroupCol])
        }}, server = TRUE)
})
observeEvent(input$deagroupCol , {
    updateSelectizeInput(session, 'deagroup2', choices = {
        if (class(deadata()) == class(as(SummarizedExperiment(),"RangedSummarizedExperiment"))){

            if (!is.null(deadata()) & input$deagroupCol != "")
                as.character(colData(deadata())[,input$deagroupCol])
        }}, server = TRUE)
})
observe({
    updateSelectizeInput(session, 'deagroupCol', choices = {
        if(!is.null(deadata())) as.character(colnames(colData(deadata())))
    }, server = TRUE)
})
