# Update

some utils command:

git remote -v


## To update:

git fetch upstream
git checkout -b update/v1.3.0

git merge upstream/master
--SOLVE CONFLICTS IF ANY--

git push origin update/v1.3.0

Create a pull request to merge `update/v1.3.0` into `master` branch.

And then merge it!!
