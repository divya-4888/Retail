library(dplyr) 
library(randomForest) 
library(tidyr)
library(tree)
library(pROC)
library(cvTools)
library(car)

setwd("E:/DATA ANALYTICS JOURNEY/R Edvancer/PROJECT 2 RETAIL")
store_train=read.csv("store_train.csv",stringsAsFactors = F)
store_test=read.csv("store_test.csv",stringsAsFactors = F)

store_test$store=NA
store_train$data='train'
store_test$data='test'
View(store_test)
View(store_train)
store_all=rbind(store_train,store_test)
glimpse(store_all)

sum(unique(table(store_all$state_alpha)))

store_all=store_all %>% 
  select(-state_alpha)

store_all=store_all %>% 
  select(-countyname)

store_all=store_all %>% 
  select(-countytownname)

store_all=store_all %>% 
  select(-Areaname)

store_all$population[is.na(store_all$population)]=round(mean(store_all$population,na.rm=T),0)
store_all$country[is.na(store_all$country)]=round(mean(store_all$country,na.rm=T),0)

CreateDummies=function(data,var,freq_cutoff=0){
  t=table(data[,var])
  t=t[t>freq_cutoff]
  t=sort(t)
  categories=names(t)[-1]
  
  for( cat in categories){
    name=paste(var,cat,sep="_")
    name=gsub(" ","",name)
    name=gsub("-","_",name)
    name=gsub("\\?","Q",name)
    name=gsub("<","LT_",name)
    name=gsub("\\+","",name)
    name=gsub("\\/","_",name)
    name=gsub(">","GT_",name)
    name=gsub("=","EQ_",name)
    name=gsub(",","",name)
    
    data[,name]=as.numeric(data[,var]==cat)
  }
  
  data[,var]=NULL
  return(data)
}

char_logical=sapply(store_all,is.character)
cat_cols=names(store_all)[char_logical]
cat_cols=cat_cols[!(cat_cols %in% c('data','store'))]
cat_cols


for(col in cat_cols){
  store_all=CreateDummies(store_all,col,50)
}

glimpse(store_all)

store_all=store_all[!((is.na(store_all$store)) & store_all$data=='train'), ]
for(col in names(store_all)){
  if(sum(is.na(store_all[,col]))>0 & !(col %in% c("data","store"))){
    store_all[is.na(store_all[,col]),col]=mean(store_all[store_all$data=='train',col],na.rm=T)
  }
}

any(is.na(store_all))
sum(is.na(store_all)) # For entire dataset
colSums(is.na(store_all)) #it is for response var

#Thus data preparation is done,  seperate both test n train data.
store_train=store_all %>% filter(data=='train') %>% select(-data)
store_test=store_all %>% filter(data=='test') %>% select(-data,-store)

set.seed(2)
s=sample(1:nrow(store_train),0.75*nrow(store_train))
train_75=store_train[s,] 
test_25=store_train[-s,]


#lets remove vars which have redundant information first on the basis of vif
for_vif=lm(store~.-Id-sales0-sales2-sales3-sales1,data=train_75)
sort(vif(for_vif),decreasing = T)[1:3]


summary(for_vif)

##Build Logistic Model

fit=glm(store~.-Id-sales0-sales2-sales3-sales1,data=train_75) #32 predictor var
fit=step(fit)


summary(fit)

formula(fit)
fit=glm(store ~ sales4 + CouSub + population + storecode_METRO12620N23019 + 
          storecode_METRO14460MM1120,data=train_75) #32 predictor var

library(pROC)
scoreLG=predict(fit,newdata =test_25,type = "response")
roccurve=roc(test_25$store,scoreLG) 
auc(roccurve)

#decision tree
library(tree)
DT= tree(as.factor(store)~.-Id,data=train_75)

DTscore=predict(DT,newdata=test_25,type="vector")[,2]
auc(roc(test_25$store,DTscore))

#Try Random Forest
library(randomForest) 

rf.model3= randomForest(as.factor(store)~.-Id,data=train_75)
test.score3=predict(rf.model3,newdata=test_25,type="prob")[,2]
auc(roc(test_25$store,test.score3))

#Random Forest for Parameter tunning

library(cvTools)

store_train$store=as.factor(store_train$store)
glimpse(store_train)

#Use full train data because here we are doing CV

#Parameter value we want to try out
#mtry: There will be upperlimit.Upperlimit means no of predictor in the data. Good idea is to start with 4 or 5 then go to no of variables in the data
#ntree:This is number of trees in the forest.There is no limit on it as such , a good starting point is 10 to 500 and you can try out values as large as 1000,5000. Although very high number of trees make sense when the data is huge as well. Default value is 500.
#maxnodes:start with 5 there is, there is no limiton this as such but good range to try can be between 1 to 20. Default value is 1.
#nodesize:There is no limit on this as such but good range to try can be between 1 to 20. Default value is 1.If values comes at edge then try to expand

param=list(mtry=c(3,4,6,8,10),
           ntree=c(50,100,200,500,700,800,900), 
           maxnodes=c(5,10,15,20,30,50,100,300,500,600,700),
           nodesize=c(1,2,5,10,20,30,40)       
)
mycost_auc=function(store,yhat){  #Real #Predicted
  roccurve=pROC::roc(store,yhat)
  score=pROC::auc(roccurve)
  return(score)
}  



#We are looking at 5*7*11*7 combination. Hence it will took an hour to run

## Function for selecting random subset of params


subset_paras=function(full_list_para,n=10){  #n=10 is default, you can give higher value
  
  all_comb=expand.grid(full_list_para)
  
  s=sample(1:nrow(all_comb),n)
  
  subset_para=all_comb[s,]
  
  return(subset_para)
}

num_trial=100
my_params=subset_paras(param,num_trial)
my_params

myauc=0


for(i in 1:num_trial){  
  print(paste('starting iteration :',i))
  # uncomment the line above to keep track of progress
  params=my_params[i,]
  
  k=cvTuning(randomForest,
             store~.-Id, 
             data =store_train,
             tuning =params,
             folds = cvFolds(nrow(store_train), K=15, type ="random"),
             cost =mycost_auc, 
             seed =2,
             predictArgs = list(type="prob"))
  
  score.this=k$cv[,2]
  
  ## trying 2695 combinations 
  
  
  if(score.this>myauc){
    print(params)
   
    myauc=score.this
    print(myauc)
    
    print(myauc)
    best_params=params
  }
  print('DONE')
}

myauc

best_params
ci.rf.final=randomForest(store~.-Id,
                         mtry=best_params$mtry,
                         ntree=best_params$ntree,
                         maxnodes=best_params$maxnodes,
                         nodesize=best_params$nodesize,
                         data=store_train
)

test.score_final=predict(ci.rf.final,newdata=store_test, type="prob")[,2]
write.csv(test.score_final,'Divya_singh_P2_part2.csv',row.names = F)
