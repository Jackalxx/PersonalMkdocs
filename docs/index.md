# 關於此專案

個人知識庫的懶人配置, 使用mkdocs管理, 並使用docker或github pages發布　　

## 如何使用

1. 在docs/Document/Publish底下放你想要的目錄結構和md檔案, 專案會預設將此目錄下的文件都放上網站  
2. 如果你想放其他目錄, 查一下mkdocs.yml的寫法然後任意調整  
3. 確保你有安裝好python, docker等服務

## Docker發布
1. 在cmd window內執行docker-compose up指令  
2. 可以搭配個人簡易nginx將/doc路徑對應到外部, 不用暴露port

## Github Page發布
1. 確認你有設定好github page資訊  
    - 前往你的 GitHub 專案頁面  
    - 點選「Settings」→「Pages」  
    - 建立Publish 分支, 並在「Source」中選擇 Publish，選擇網頁的根目錄（/(root)）  
2. 設定action允許workflow寫入
3. 將deploy.yml放置到 .github/workflows資料夾中 (如果原本沒有)
4. 做些小修改後 commit master 
